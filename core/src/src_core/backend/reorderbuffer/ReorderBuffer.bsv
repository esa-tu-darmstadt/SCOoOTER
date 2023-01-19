package ReorderBuffer;

import Vector::*;
import Inst_Types::*;
import Types::*;
import Interfaces::*;
import FIFO::*;
import SpecialFIFOs::*;
import Debug::*;
import TestFunctions::*;
import GetPut::*;

//allow the index to wrap around
//TODO: only needed if size is not pwr2, as the index can naturally overflow here
function UInt#(size_logidx_t) truncate_index(UInt#(size_logidx_t) new_idx, UInt#(size_logidx_t) add) provisos (
    Add#(1, size_logidx_t, size_log_t),

    // needed to test if robdepth is a pwr of two
    Log#(ROBDEPTH, robdepth_log_t),
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
    end else output_idx = new_idx + add;

    return output_idx;
endfunction

(* synthesize *)
module mkReorderBuffer(RobIFC);
    let m <- mkReorderBuffer_in();
    return m;
endmodule

module mkReorderBuffer_in(RobIFC) provisos (
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),
    Add#(ROBDEPTH, 1, size_pad_t),
    Log#(size_pad_t, size_log_t),
    Log#(ROBDEPTH, size_logidx_t),
    Add#(__a, issuewidth_log_t, size_log_t),
    Add#(a__, size_logidx_t, size_log_t),
    Max#(issuewidth_log_t, size_logidx_t, count_width_t)
);

    Wire#(Vector#(NUM_FU, Maybe#(Result))) result_bus_vec <- mkWire();

    //internal store
    Vector#(ROBDEPTH, Array#(Reg#(RobEntry))) internal_store_v <- replicateM(mkCReg(2, unpack(0)));
    Vector#(ROBDEPTH, Reg#(RobEntry)) internal_store_port0_v = Vector::map(disassemble_creg(0), internal_store_v);
    Vector#(ROBDEPTH, Reg#(RobEntry)) internal_store_port1_v = Vector::map(disassemble_creg(1), internal_store_v);
    //pointers for head and tail
    Reg#(UInt#(size_logidx_t)) head_r <- mkReg(0);
    Reg#(UInt#(size_logidx_t)) tail_r <- mkReg(0);
    //as empty and full states look similar if only
    //head and tail are regarded, we add a flag to
    //avoid sacrificing one storage space
    Reg#(Bool) full_r[2] <- mkCReg(2, False);

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
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            let idx = truncate_index(tail_r, fromInteger(i));
            let inst = internal_store_port0_v[idx];
            if(!done && (fromInteger(i) < full_slots()))
                if(inst.result matches tagged Tag .e)
                    done = True;
                else
                    cnt = cnt + 1;
        end
        return cnt;
    endfunction

    //find out how many slots are empty
    function UInt#(size_log_t) empty_slots;
        return fromInteger(valueOf(ROBDEPTH)) - full_slots();
    endfunction

    //caller has to guard that buffer does not overflow!
    function Action reserve_fun(Vector#(ISSUEWIDTH, RobEntry) new_entries, UInt#(issuewidth_log_t) count);
        action
            if(empty_slots() < extend(count)) begin
                err_print(ROB, $format("Error while insert - inserting too much! - free: ", empty_slots, " in: ", count));
            end

            Vector#(ROBDEPTH, RobEntry) local_values = Vector::readVReg(internal_store_port1_v);

            // insert elements
            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                // calculate new idx
                let new_idx = truncate_index(head_r, fromInteger(i));
                if(fromInteger(i) < count)
                    local_values[new_idx] = new_entries[i];
            end

            Vector::writeVReg(internal_store_port1_v, local_values);

            UInt#(count_width_t) count_ext = extend(count);
            // calculate new head
            head_r <= truncate_index(head_r, truncate(count_ext));
            // set full flag if full
            if(tail_r == truncate_index(head_r, truncate(count_ext))) full_r[0] <= True;
        endaction
    endfunction

    function Vector#(ISSUEWIDTH, RobEntry) retrieve_fun();
            Vector#(ISSUEWIDTH, RobEntry) tmp_res;

            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                // calculate new idx
                let deq_idx = truncate_index(tail_r, fromInteger(i));
                tmp_res[i] = internal_store_port0_v[deq_idx];
            end

            return tmp_res;
    endfunction

    function Action deq_instructions(UInt#(issuewidth_log_t) count);
        action
            // calculate new tail
            UInt#(count_width_t) count_ext = extend(count);
            tail_r <= truncate_index(tail_r, truncate(count_ext));
            if(count > 0) full_r[1] <= False;
        endaction
    endfunction


    function Bool test_result(UInt#(TLog#(ROBDEPTH)) current_tag, Maybe#(Result) res);
        return (res matches tagged Valid .res_v &&& res_v.tag == current_tag ? True : False);
    endfunction
    rule read_cdb;
        dbg_print(ROB, $format("result_bus: ", fshow(result_bus_vec)));
        Vector#(ROBDEPTH, RobEntry) local_store = Vector::readVReg(internal_store_port0_v);

        for(Integer i = 0; i < valueOf(ROBDEPTH); i=i+1) begin
            let current_entry = local_store[i];

            if(current_entry. result matches tagged Tag .tag) begin
                let produced_result = Vector::find(test_result(tag), result_bus_vec);

                if(produced_result matches tagged Valid .found_result &&&
                   found_result matches tagged Valid .unpacked_result) begin

                    //writes
                    current_entry.mem_wr = unpacked_result.mem_wr;

                    case (unpacked_result.result) matches
                        tagged Result .r : current_entry.result = tagged Result r;
                        tagged Except .e : current_entry.result = tagged Except e;
                    endcase
                    //next pc
                    case (unpacked_result.new_pc) matches
                        tagged Valid .v: current_entry.next_pc = v;
                        tagged Invalid : current_entry.next_pc = current_entry.pc+4;
                    endcase

                end

            end

            local_store[i] = current_entry;


        end

        Vector::writeVReg(internal_store_port0_v, local_store);


    endrule

    rule debug_print_full_contents;
        //dbg_print(ROB, $format("Head: ", head_r, " Tail: ", tail_r));
        Bool done = False;
        for(Integer i = 0; i<valueOf(ROBDEPTH); i=i+1) begin
            let current_ptr = truncate_index(tail_r, fromInteger(i));

            if( (current_ptr != head_r || full_r[0]) && !done )
                dbg_print(ROB, $format("Stored ", i, " ", fshow(internal_store_port0_v[current_ptr])));
            else done = True;
        end
    endrule

    FIFO#(Vector#(ISSUEWIDTH, RobEntry)) reserve_buffer_data <- mkBypassFIFO();
    FIFO#(UInt#(issuewidth_log_t)) reserve_buffer_count <- mkBypassFIFO();

    //(* conflict_free = "read_cdb, process_reservation" *)
    rule process_reservation;
        reserve_buffer_data.deq();
        reserve_buffer_count.deq();

        reserve_fun(reserve_buffer_data.first(), reserve_buffer_count.first());
    endrule

    Wire#(UInt#(issuewidth_log_t)) ready_precalc <- mkBypassWire();
    Wire#(UInt#(size_log_t)) empty_precalc <- mkBypassWire();

    rule bypass_rdy;
        ready_precalc <= ready();
    endrule

    rule bypass_free;
        empty_precalc <= empty_slots();
    endrule

    method UInt#(issuewidth_log_t) available = ready_precalc;
    method UInt#(size_log_t) free = empty_precalc;
    method UInt#(size_logidx_t) current_idx = head_r;
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, UInt#(issuewidth_log_t) num);
        action
        reserve_buffer_data.enq(data);
        reserve_buffer_count.enq(num);
        endaction
    endmethod
    method Vector#(ISSUEWIDTH, RobEntry) get();
        return retrieve_fun();
    endmethod
    method Action complete_instructions(UInt#(issuewidth_log_t) count);
    action
        deq_instructions(count);
    endaction
    endmethod

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);
        result_bus_vec <= bus_in;
    endmethod
    
endmodule

endpackage