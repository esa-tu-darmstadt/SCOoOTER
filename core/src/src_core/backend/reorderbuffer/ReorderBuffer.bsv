package ReorderBuffer;

/*
  The REORDER BUFFER stores instructions in order.
  It sniffs the result bus and marks instructions as complete.
  Complete instructions at the tail can be dequeued in programm
  order. New instructions enter at the head.

  The ROB is basically a ring buffer.

  The ROB also provides signals to CSR and LSU to guard their
  reordering.
*/

import Vector::*;
import Inst_Types::*;
import Types::*;
import Interfaces::*;
import FIFO::*;
import SpecialFIFOs::*;
import Debug::*;
import TestFunctions::*;
import GetPut::*;
import ClientServer::*;
import BuildVector::*;
import Ehr::*;
import FIFOF::*;

//allow the index to wrap around
//only needed if size is not pwr2, as the index can naturally overflow here
function UInt#(size_logidx_t) truncate_index(UInt#(size_logidx_t) new_idx, UInt#(size_logidx_t) add) provisos (
    // calculate size of a word to track entries in ROB
    Add#(1, size_logidx_t, size_log_t),
    Log#(ROBDEPTH, robdepth_log_t),
    // create types to test if depth is pwr of 2
    Add#(1, robdepth_dec_t, ROBDEPTH),
    Max#(1, robdepth_dec_t, robdepth_dec_pos_t),
    Log#(robdepth_dec_pos_t, robdepth_test_t)
);

    UInt#(size_logidx_t) output_idx;

    //if ROBDEPTH is not a pwr of two, explicitly implement rollover
    if( valueOf(robdepth_log_t) == valueOf(robdepth_test_t) ) begin
        UInt#(size_log_t) new_idx_ext = extend(new_idx);
        UInt#(size_log_t) add_ext = extend(add);
        UInt#(size_log_t) max_idx = fromInteger(valueOf(ROBDEPTH));
        UInt#(size_log_t) overflow_idx = new_idx_ext + add_ext;
        output_idx = overflow_idx >= max_idx ?
                        truncate( overflow_idx - max_idx ) :
                        truncate( overflow_idx );
    // if robdepth is power of two, the index will roll over naturally
    // this is more efficient!
    end else output_idx = new_idx + add;

    return output_idx;
endfunction

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkReorderBuffer(RobIFC);
    let m <- mkReorderBuffer_in();
    return m;
endmodule

module mkReorderBuffer_in(RobIFC) provisos (
    // create types to track instruction amounts
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),
    // create types to track entries in ROB
    Add#(ROBDEPTH, 1, size_pad_t),
    Log#(size_pad_t, size_log_t),
    Log#(ROBDEPTH, size_logidx_t),
    //the depth of the ROB must be deeper than the issuewidth
    Add#(__a, issuewidth_log_t, size_log_t),
    Max#(issuewidth_log_t, size_logidx_t, count_width_t)
);

    `ifdef LOG_PIPELINE
        Reg#(UInt#(XLEN)) clk_ctr <- mkReg(0);
        rule count_clk; clk_ctr <= clk_ctr + 1; endrule
        Reg#(File) out_log <- mkRegU();
        Reg#(File) out_log_ko <- mkRegU();
        rule open if (clk_ctr == 0);
            File out_log_l <- $fopen("scoooter.log", "a");
            out_log <= out_log_l;
            File out_log_kol <- $fopen("konata.log", "a");
            out_log_ko <= out_log_kol;
        endrule
    `endif

    // wire to distribute result bus
    Wire#(Vector#(NUM_FU, Maybe#(Result))) result_bus_vec <- mkWire();

    //internal storage
    Vector#(ROBDEPTH, Reg#(RobEntry)) internal_store_v <- replicateM(mkRegU());
    //separate the ports
    Wire#(Vector#(ROBDEPTH, RobEntry)) internal_store_preread_v <- mkBypassWire();
    //pointers for head and tail
    Reg#(UInt#(size_logidx_t)) head_r <- mkReg(0);
    Reg#(UInt#(size_logidx_t)) tail_r <- mkReg(0);
    //as empty and full states look similar if only
    //head and tail are regarded, we add a flag to
    //avoid sacrificing one storage space
    Ehr#(2, Bool) full_r <- mkEhr(False);

    // helper function to and two bools
    function Bool andd(Bool a, Bool b) = (a && b);

    //find out how many slots are full
    function UInt#(size_log_t) full_slots;
        UInt#(size_log_t) result;

        //calculate from head and tail pointers
        if (head_r > tail_r) result = extend(head_r) - extend(tail_r);
        else if (tail_r > head_r) result = fromInteger(valueOf(ROBDEPTH)) - extend(tail_r) + extend(head_r);
        // if both pointers are equal, must be full or empty
        else if (full_r[0]) result = fromInteger(valueOf(ROBDEPTH));
        else result = 0;

        return result;
    endfunction

    //calculate how many instructions at HEAD are ready
    function UInt#(issuewidth_log_t) ready();
        UInt#(issuewidth_log_t) cnt = 0;
        Bool done = False;
        // loop through buffer
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            let idx = truncate_index(tail_r, fromInteger(i));
            let inst = internal_store_v[idx];
            // test for completed instructions
            if(!done && (fromInteger(i) < full_slots()))
                if(inst.result matches tagged Tag .e)
                    done = True;
                else
                    cnt = cnt + 1;
        end
        return cnt;
    endfunction

    //find out how many slots are empty
    function UInt#(size_log_t) empty_slots = fromInteger(valueOf(ROBDEPTH)) - full_slots();

    // reserve space in the ROB
    // this means, enqueue new instructions
    // called from ISSUE
    // caller has to guard that buffer does not overflow!
    Wire#(Tuple2#(Vector#(ISSUEWIDTH, RobEntry), UInt#(issuewidth_log_t))) reserve_data_w <- mkWire();
    rule reserve_fun;
            let new_entries = tpl_1(reserve_data_w);
            let count = tpl_2(reserve_data_w);
            // print an error in simulation if the buffer is too full to hold the new instructions
            if(empty_slots() < extend(count)) begin
                err_print(ROB, $format("Error while insert - inserting too much! - free: ", empty_slots, " in: ", count));
            end

            // loop over elements
            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                // calculate idx of insertion
                let new_idx = truncate_index(head_r, fromInteger(i));
                if(fromInteger(i) < count)
                    internal_store_v[new_idx] <= new_entries[i]; // insert entry
            end

            // update pointers
            UInt#(count_width_t) count_ext = extend(count);
            // calculate new head
            head_r <= truncate_index(head_r, truncate(count_ext));
            // set full flag if full
            if(count > 0 && tail_r == truncate_index(head_r, truncate(count_ext))) full_r[0] <= True;
    endrule

    // take functions out of the ROB
    // called from Commit
    // provides at most ISSUEWIDTH entries
    // does not update the pointers, think of first() compared to deq()
    function Vector#(ISSUEWIDTH, RobEntry) retrieve_fun();
            Vector#(ISSUEWIDTH, RobEntry) tmp_res;

            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                let deq_idx = truncate_index(tail_r, fromInteger(i));
                tmp_res[i] = internal_store_v[deq_idx];
            end

            return tmp_res;
    endfunction

    // dequeue instructions from ROB
    // move tail pointer to exclude count instructions
    function Action deq_instructions(UInt#(issuewidth_log_t) count);
        action
            // calculate new tail
            UInt#(count_width_t) count_ext = extend(count);
            tail_r <= truncate_index(tail_r, truncate(count_ext));
            if(count > 0) full_r[1] <= False;
        endaction
    endfunction

    // helper function to check if a result has a certain tag
    function Bool test_result(UInt#(TLog#(ROBDEPTH)) current_tag, Maybe#(Result) res)
        = isValid(res) && res.Valid.tag == current_tag;

    rule bypass_cdb;
        internal_store_preread_v <= Vector::readVReg(internal_store_v);
    endrule
    // read the result bus
    (* conflict_free="reserve_fun,read_cdb" *)
    rule read_cdb;
        // debug print
        dbg_print(ROB, $format("result_bus: ", fshow(result_bus_vec)));

        // for every ROB entry
        for(Integer i = 0; i < valueOf(ROBDEPTH); i=i+1) begin
            let current_entry = internal_store_preread_v[i];

            // check if the entry is tagged
            if(current_entry.result matches tagged Tag .tag) begin
                // look for a fitting result
                let produced_result = Vector::find(test_result(tag), result_bus_vec);

                // unpack the result if it was found
                if(produced_result matches tagged Valid .found_result &&&
                   found_result matches tagged Valid .unpacked_result) begin

                    // unpack the result or the exception
                    current_entry.result = case (unpacked_result.result) matches
                        tagged Result .r : tagged Result r;
                        tagged Except .e : tagged Except e;
                    endcase;

                    `ifdef RVFI
                        current_entry.mem_addr = unpacked_result.mem_addr;
                    `endif

                    // generate the next pc field from the result
                    current_entry.next_pc = case (unpacked_result.new_pc) matches
                        tagged Valid .v : truncateLSB(v);
                        tagged Invalid  : truncateLSB(current_entry.pc+1);
                    endcase;

                    // update entry
                    internal_store_v[i] <= current_entry;

                    `ifdef LOG_PIPELINE
                        $fdisplay(out_log, "%d COMPLETE %x %d %d", clk_ctr, current_entry.pc, i, current_entry.epoch);
                        $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, current_entry.log_id, 0, "E");
                    `endif
                end
            end
        end
    endrule

    // print rob content for debugging
    rule debug_print_full_contents;
        Bool done = False;
        for(Integer i = 0; i<valueOf(ROBDEPTH); i=i+1) begin
            let current_ptr = truncate_index(tail_r, fromInteger(i));

            if( (current_ptr != head_r || full_r[0]) && !done )
                dbg_print(ROB, $format("Stored ", i, " ", fshow(internal_store_v[current_ptr])));
            else done = True;
        end
    endrule

    // propagate count and instructions
    Wire#(UInt#(issuewidth_log_t)) deq_bypass <- mkWire();
    rule dequeue_insts;
        deq_instructions(deq_bypass);
    endrule
    FIFOF#(Tuple2#(Vector#(ISSUEWIDTH, RobEntry), UInt#(issuewidth_log_t))) insts_passing <-
        (valueOf(ROB_LATCH_OUTPUT) == 1 ? mkPipelineFIFOF() : mkBypassFIFOF());
    Reg#(UInt#(size_logidx_t)) tail_delay_r <- (valueOf(ROB_LATCH_OUTPUT) == 1 ?  mkReg(0) : mkWire());
    rule collect_instructions;
        if (valueOf(ROB_LATCH_OUTPUT) == 1) deq_bypass <= ready();
        insts_passing.enq(tuple2(retrieve_fun(), ready())); // look at first avail. inst
        tail_delay_r <= tail_r;
    endrule

    // used to bypass request/response pairs in server
    FIFO#(UInt#(TLog#(ROBDEPTH))) fwd_test_mem_f <- mkBypassFIFO();

    method UInt#(issuewidth_log_t) available = tpl_2(insts_passing.first()); // how many inst can be dequeued?
    method UInt#(size_log_t) free = empty_slots(); // how many inst can be enqueued?
    method UInt#(size_logidx_t) current_idx = head_r; // head ptr for idx generation
    method UInt#(size_logidx_t) current_tail_idx = (valueOf(ROB_LATCH_OUTPUT) == 1 ? tail_delay_r : tail_r); // tail ptr for atomic predication
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, UInt#(issuewidth_log_t) num)
        = reserve_data_w._write(tuple2(data, num)); // put instructions into ROB
    method ActionValue#(Vector#(ISSUEWIDTH, RobEntry)) get();
        if (valueOf(ROB_LATCH_OUTPUT) == 0) deq_bypass <= ready();
        insts_passing.deq();
        return tpl_1(insts_passing.first());
    endmethod
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);
        result_bus_vec._write(res_bus); // connect to result bus
    endmethod
    
endmodule

endpackage
