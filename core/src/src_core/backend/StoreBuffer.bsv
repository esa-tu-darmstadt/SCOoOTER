package StoreBuffer;

import FIFO::*;
import SpecialFIFOs::*;
import Types::*;
import Inst_Types::*;
import Interfaces::*;
import GetPut::*;
import Vector::*;
import TestFunctions::*;

interface InternalStoreIFC#(numeric type entries);
    method Action enq(UInt#(TLog#(TAdd#(ISSUEWIDTH, 1))) count, Vector#(ISSUEWIDTH, MemWr) data);
    method Bool enqReadyN(UInt#(TLog#(TAdd#(ISSUEWIDTH, 1))) count);
    method Action deq();
    method MemWr first();
    method Maybe#(MaskedWord) forward(UInt#(XLEN) addr);
endinterface


function UInt#(size_logidx_t) truncate_index(UInt#(size_logidx_t) new_idx, UInt#(size_logidx_t) add) provisos (
    Add#(1, size_logidx_t, size_log_t),
    // needed to test if depth is a pwr of two
    Log#(16, depth_log_t),
    Add#(1, depth_dec_t, 16),
    Max#(1, depth_dec_t, depth_dec_pos_t),
    Log#(depth_dec_pos_t, depth_test_t)
);
    UInt#(size_logidx_t) output_idx;

    //if ROBDEPTH is not a pwr of two, explicitly implement rollover
    if( valueOf(depth_log_t) == valueOf(depth_test_t) ) begin

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

module mkInternalStore(InternalStoreIFC#(entries)) provisos (
    Add#(entries, 1, size_pad_t),
    Log#(size_pad_t, size_log_t),
    Log#(entries, size_logidx_t),
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),
    Add#(a__, size_logidx_t, size_log_t),
    Add#(b__, 3, size_logidx_t),
    Add#(c__, 3, size_log_t)
);

    Reg#(UInt#(size_logidx_t)) head_r <- mkReg(0);
    Reg#(UInt#(size_logidx_t)) tail_r <- mkReg(0);
    Reg#(Bool) full_r[2] <- mkCReg(2, False);

    Vector#(entries, Reg#(MemWr)) storage <- replicateM(mkRegU());

    function UInt#(size_log_t) full_slots;
        UInt#(size_log_t) result;

        //calculate from head and tail pointers
        if (head_r > tail_r) result = extend(head_r) - extend(tail_r);
        else if (tail_r > head_r) result = fromInteger(valueOf(entries)) - extend(tail_r) + extend(head_r);
        // if both pointers are equal, must be full or empty
        else if (full_r[0]) result = fromInteger(valueOf(entries));
        else result = 0;

        return result;
    endfunction
    function UInt#(size_log_t) empty_slots;
        return fromInteger(valueOf(entries)) - full_slots();
    endfunction

    PulseWire remove_entry <- mkPulseWire();

    rule clear if (remove_entry);
        tail_r <= truncate_index(tail_r, 1);
        full_r[1] <= False;
    endrule

    method Action enq(UInt#(issuewidth_log_t) count, Vector#(ISSUEWIDTH, MemWr) data);
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            // calculate new idx
            let new_idx = truncate_index(head_r, fromInteger(i));
            if(fromInteger(i) < count)
                storage[new_idx] <= data[i];
        end
        head_r <= truncate_index(head_r, extend(count));
        // set full flag if full
        if(tail_r == truncate_index(head_r, extend(count))) full_r[0] <= True;
    endmethod
    method Bool enqReadyN(UInt#(issuewidth_log_t) count) = empty_slots >= extend(count);
    method Action deq() if (full_slots > 0);
        remove_entry.send();
    endmethod
    method MemWr first() if (full_slots > 0);
        return storage[tail_r];
    endmethod
    method Maybe#(MaskedWord) forward(UInt#(XLEN) addr);
        Maybe#(MaskedWord) result = tagged Invalid;
        for(Integer i = 0; i < valueOf(entries); i=i+1) begin
            let current_idx = truncate_index(tail_r, fromInteger(i));
            if(current_idx != head_r || full_r[0] && addr == storage[current_idx].mem_addr) begin
                result = tagged Valid MaskedWord { data: storage[current_idx].data, store_mask: storage[current_idx].store_mask };
            end
        end
        return result;
    endmethod
endmodule



(* synthesize *)
module mkStoreBuffer(StoreBufferIFC);

    InternalStoreIFC#(16) internal_buf <- mkInternalStore;
    Wire#(Vector#(ISSUEWIDTH, Maybe#(MemWr))) input_bypass_w <- mkDWire(replicate(tagged Invalid));
    FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) in_f <- mkPipelineFIFO();

    rule generate_flatten;
        let writes_in = tpl_1(in_f.first());
        let cnt_in = tpl_2(in_f.first());

        // remove entries beyond count
        Vector#(ISSUEWIDTH, Maybe#(MemWr)) cleaned_maybes;
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            cleaned_maybes[i] = fromInteger(i) < cnt_in ? writes_in[i] : tagged Invalid;
        end

        input_bypass_w <= cleaned_maybes;
    endrule

    rule flatten_incoming;
        let writes_in = tpl_1(in_f.first());
        let cnt_in = tpl_2(in_f.first());

        // remove entries beyond count
        Vector#(ISSUEWIDTH, Maybe#(MemWr)) cleaned_maybes;
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            cleaned_maybes[i] = fromInteger(i) < cnt_in ? writes_in[i] : tagged Invalid;
        end

        // remove empty slots between requests
        Vector#(ISSUEWIDTH, Maybe#(MemWr)) flattened_maybes = ?;
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            flattened_maybes[i] = find_nth_valid(i, writes_in);
        end

        // count number of elements
        Vector#(ISSUEWIDTH, MemWr) flattened = Vector::map(fromMaybe(?), flattened_maybes);
        let count = Vector::countIf(isValid, cleaned_maybes);

        // display for debugging
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            if(fromInteger(i) < count) begin
                //$display(fshow(flattened[i]));
            end
        end

        //put into MIMO buffer
        if(internal_buf.enqReadyN(count)) begin
            in_f.deq();
            internal_buf.enq(count, flattened);
        end
    endrule

    function Bool find_addr(UInt#(XLEN) addr, Maybe#(MemWr) mw) = (mw matches tagged Valid .w ? w.mem_addr == addr : False); 
    function MaskedWord mw_from_memory_write(MemWr in) = MaskedWord {data: in.data, store_mask: in.store_mask};
    method Maybe#(MaskedWord) forward(UInt#(XLEN) addr);
        let store_result = internal_buf.forward(addr);
        let in_result = Vector::find(find_addr(addr), Vector::reverse(input_bypass_w));
        let in_result_fm = fromMaybe(tagged Invalid, in_result);
        Maybe#(MaskedWord) in_result_conv = (in_result_fm matches tagged Valid .v ? tagged Valid mw_from_memory_write(v) : tagged Invalid);
        let result = in_result matches tagged Valid .v ? in_result_conv : store_result;

        return result;
    endmethod

    interface Put memory_writes;
        method Action put(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1)))) in);
            in_f.enq(in);
        endmethod
    endinterface

    interface Get write;
        method ActionValue#(MemWr) get();
            actionvalue
                internal_buf.deq();
                return internal_buf.first();
            endactionvalue
        endmethod
    endinterface
endmodule

endpackage