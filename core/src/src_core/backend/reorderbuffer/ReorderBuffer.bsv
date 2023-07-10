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

    // wire to distribute result bus
    Wire#(Vector#(NUM_FU, Maybe#(FullResult))) result_bus_vec <- mkWire();

    //internal storage
    Vector#(ROBDEPTH, Array#(Reg#(RobEntry))) internal_store_v <- replicateM(mkCReg(2, unpack(0)));
    //separate the ports
    Vector#(ROBDEPTH, Reg#(RobEntry)) internal_store_port0_v = Vector::map(disassemble_creg(0), internal_store_v);
    Vector#(ROBDEPTH, Reg#(RobEntry)) internal_store_port1_v = Vector::map(disassemble_creg(1), internal_store_v);
    //pointers for head and tail
    Reg#(UInt#(size_logidx_t)) head_r <- mkReg(0);
    Reg#(UInt#(size_logidx_t)) tail_r <- mkReg(0);
    //as empty and full states look similar if only
    //head and tail are regarded, we add a flag to
    //avoid sacrificing one storage space
    Reg#(Bool) full_r[2] <- mkCReg(2, False);

    // those functions test if a pending write to memory or CSR space is in the current instruction
    function Bool pending_write(RobEntry re) = (re.write matches tagged Mem .v ? True : (re.write matches tagged Pending_mem ? True : False)); 
    function Bool pending_csr(RobEntry re) = (re.write matches tagged Csr .v ? True : False); 
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
            let inst = internal_store_port0_v[idx];
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
    function Action reserve_fun(Vector#(ISSUEWIDTH, RobEntry) new_entries, UInt#(issuewidth_log_t) count);
        action
            // print an error in simulation if the buffer is too full to hold the new instructions
            if(empty_slots() < extend(count)) begin
                err_print(ROB, $format("Error while insert - inserting too much! - free: ", empty_slots, " in: ", count));
            end

            Vector#(ROBDEPTH, RobEntry) local_values = Vector::readVReg(internal_store_port1_v);
            // loop over elements
            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                // calculate idx of insertion
                let new_idx = truncate_index(head_r, fromInteger(i));
                if(fromInteger(i) < count)
                    local_values[new_idx] = new_entries[i]; // insert entry
            end
            Vector::writeVReg(internal_store_port1_v, local_values);

            // update pointers
            UInt#(count_width_t) count_ext = extend(count);
            // calculate new head
            head_r <= truncate_index(head_r, truncate(count_ext));
            // set full flag if full
            if(count > 0 && tail_r == truncate_index(head_r, truncate(count_ext))) full_r[0] <= True;
        endaction
    endfunction

    // take functions out of the ROB
    // called from Commit
    // provides at most ISSUEWIDTH entries
    // does not update the pointers, think of first() compared to deq()
    function Vector#(ISSUEWIDTH, RobEntry) retrieve_fun();
            Vector#(ISSUEWIDTH, RobEntry) tmp_res;

            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                let deq_idx = truncate_index(tail_r, fromInteger(i));
                tmp_res[i] = internal_store_port0_v[deq_idx];
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
    function Bool test_result(UInt#(TLog#(ROBDEPTH)) current_tag, Maybe#(FullResult) res)
        = isValid(res) && res.Valid.tag == current_tag;

    // read the result bus
    rule read_cdb;
        // debug print
        dbg_print(ROB, $format("result_bus: ", fshow(result_bus_vec)));
        Vector#(ROBDEPTH, RobEntry) local_store = Vector::readVReg(internal_store_port0_v);

        // for every ROB entry
        for(Integer i = 0; i < valueOf(ROBDEPTH); i=i+1) begin
            let current_entry = local_store[i];

            // check if the entry is tagged
            if(current_entry.result matches tagged Tag .tag) begin
                // look for a fitting result
                let produced_result = Vector::find(test_result(tag), result_bus_vec);

                // unpack the result if it was found
                if(produced_result matches tagged Valid .found_result &&&
                   found_result matches tagged Valid .unpacked_result) begin

                    // extract CSR and Mem writes
                    current_entry.write = (unpacked_result.write matches tagged Mem .v ? tagged Mem v : 
                                           unpacked_result.write matches tagged Csr .v ? tagged Csr v : tagged None);

                    // unpack the result or the exception
                    current_entry.result = case (unpacked_result.result) matches
                        tagged Result .r : tagged Result r;
                        tagged Except .e : tagged Except e;
                    endcase;

                    // generate the next pc field from the result
                    current_entry.next_pc = case (unpacked_result.new_pc) matches
                        tagged Valid .v : v;
                        tagged Invalid  : (current_entry.pc+4);
                    endcase;
                end
            end

            // update entry
            local_store[i] = current_entry;
        end

        Vector::writeVReg(internal_store_port0_v, local_store);
    endrule

    // print rob content for debugging
    rule debug_print_full_contents;
        Bool done = False;
        for(Integer i = 0; i<valueOf(ROBDEPTH); i=i+1) begin
            let current_ptr = truncate_index(tail_r, fromInteger(i));

            if( (current_ptr != head_r || full_r[0]) && !done )
                dbg_print(ROB, $format("Stored ", i, " ", fshow(internal_store_port0_v[current_ptr])));
            else done = True;
        end
    endrule

    // used to bypass request/response pairs in server
    FIFO#(UInt#(TLog#(ROBDEPTH))) fwd_test_mem_f <- mkBypassFIFO();

    method UInt#(issuewidth_log_t) available = ready(); // how many inst can be dequeued?
    method UInt#(size_log_t) free = empty_slots(); // how many inst can be enqueued?
    method UInt#(size_logidx_t) current_idx = head_r; // head ptr for idx generation
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, UInt#(issuewidth_log_t) num)
        = reserve_fun(data, num); // put instructions into ROB
    method Vector#(ISSUEWIDTH, RobEntry) get()
        = retrieve_fun(); // look at first avail. inst
    method Action complete_instructions(UInt#(issuewidth_log_t) count)
        = deq_instructions(count); // dequeue count inst.
    method Action result_bus(Tuple3#(Vector#(NUM_FU, Maybe#(Result)), Maybe#(MemWr), Maybe#(CsrWrite)) res_bus);
        let results = tpl_1(res_bus);
        ResultWrite mem_wr = isValid(tpl_2(res_bus)) ? tagged Mem tpl_2(res_bus).Valid : tagged None;
        ResultWrite csr_wr = isValid(tpl_3(res_bus)) ? tagged Csr tpl_3(res_bus).Valid : tagged None;
        Vector#(NUM_FU, ResultWrite) write_result_bus_vec = Vector::append(Vector::replicate(tagged None), vec( // zero out non-mem/csr units
            mem_wr,
            csr_wr
        ));
        function Maybe#(FullResult) parts_to_full_result(Maybe#(Result) r, ResultWrite w) = isValid(r) ? tagged Valid FullResult {
            tag : r.Valid.tag,
            new_pc : r.Valid.new_pc,
            result : r.Valid.result,
            write : w
        } : tagged Invalid;
        let full_result_bus_vec = Vector::map(uncurry(parts_to_full_result), Vector::zip(results, write_result_bus_vec));

        result_bus_vec._write(full_result_bus_vec); // connect to result bus
    endmethod

    // check if there is a blocking memory write
    //TODO: can be more efficient if checking for epoch and address
    interface Server check_pending_memory;
        interface Put request;
            // request if this inst is blocked by a mem op
            method Action put(UInt#(TLog#(ROBDEPTH)) idx) = fwd_test_mem_f.enq(idx);
        endinterface
        interface Get response;
            method ActionValue#(Bool) get();
                actionvalue
                    Vector#(ROBDEPTH, RobEntry) local_store = Vector::readVReg(internal_store_port0_v);
                    let idx = fwd_test_mem_f.first(); fwd_test_mem_f.deq();
                    //rob cannot be empty!
                    //this slice of ROB cannot be full (since the instruction for which we request is excluded)
                    Vector#(ROBDEPTH, Bool) slice_part_vector = Vector::map(part_of_rob_slice(False, idx, tail_r), Vector::map(fromInteger, Vector::genVector()));
                    Vector#(ROBDEPTH, Bool) pending_write_vector = Vector::map(pending_write, local_store);
                    Vector#(ROBDEPTH, Bool) inhibitants_map = Vector::map(uncurry(andd), Vector::zip(slice_part_vector, pending_write_vector));

                    return Vector::elem(True, inhibitants_map);
                endactionvalue
            endmethod
        endinterface
    endinterface

    // check if there is a pending CSR operation
    method Bool csr_busy();
        Vector#(ROBDEPTH, RobEntry) local_store = Vector::readVReg(internal_store_port0_v);
        Vector#(ROBDEPTH, Bool) slice_part_vector = Vector::map(part_of_rob_slice(full_r[0], head_r, tail_r), Vector::map(fromInteger, Vector::genVector()));
        Vector#(ROBDEPTH, Bool) pending_csr_vector = Vector::map(pending_csr, local_store);
        Vector#(ROBDEPTH, Bool) inhibitants_map = Vector::map(uncurry(andd), Vector::zip(slice_part_vector, pending_csr_vector));

        return Vector::countElem(True, inhibitants_map) >= 1;
    endmethod

    
endmodule

endpackage