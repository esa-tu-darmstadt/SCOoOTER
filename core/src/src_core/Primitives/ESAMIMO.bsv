package ESAMIMO;

// Notes :
// - This module works like a FIFO, but for arbitrary amounts of the base object type.
// - The clear method overrides the effects of enq and deq.

////////////////////////////////////////////////////////////////////////////////
/// Imports
////////////////////////////////////////////////////////////////////////////////
import Vector            ::*;
import FIFO              ::*;
import FIFOF             ::*;
import MIMO              ::*;
import Ehr               ::*;

////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////


module mkESAMIMO(MIMO#(max_in, max_out, size, t)) provisos (
    Bits#(t, st),              // object must have bit representation
    Log#(size, idx_t),

    Add#(d__, 1, size),

    Add#(a__, max_out_idx, fill_state_t),
    Add#(b__, max_in_idx, fill_state_t),
    Add#(c__, idx_t, fill_state_t),

    // needed for compatibility with the vanilla MIMO interface
    Log#(TAdd#(size, 1), fill_state_t),
    Log#(TAdd#(max_in, 1), max_in_idx),
    Log#(TAdd#(max_out, 1), max_out_idx),

    FShow#(Vector::Vector#(max_in, t)),

    Add#(e__, fill_state_t, TAdd#(1, idx_t))
);

    function UInt#(idx_t) truncate_index(UInt#(idx_t) new_idx, UInt#(fill_state_t) add) provisos (
        // create types to test if depth is pwr of 2
        Add#(1, size_dec_t, size),
        Max#(1, size_dec_t, size_dec_pos_t),
        Log#(size_dec_pos_t, size_test_t),

        Add#(e__, fill_state_t, overflow_state),
        Add#(1, idx_t, overflow_state)
        
    );
        
        UInt#(idx_t) output_idx;

        //if size is not a pwr of two, explicitly implement rollover
        if( valueOf(idx_t) == valueOf(size_test_t) ) begin
            UInt#(overflow_state) new_idx_ext = extend(new_idx);
            UInt#(overflow_state) add_ext = extend(add);
            UInt#(overflow_state) max_idx = fromInteger(valueOf(size));
            UInt#(overflow_state) overflow_idx = new_idx_ext + add_ext;
            output_idx = overflow_idx >= max_idx ?
                            truncate( overflow_idx - max_idx ) :
                            truncate( overflow_idx );
        // if size is power of two, the index will roll over naturally
        // this is more efficient!
        end else output_idx = new_idx + truncate(add);

        return output_idx;
    endfunction

    // fullness state
    Reg#(UInt#(idx_t)) head_r <- mkReg(0);
    Array#(Reg#(UInt#(idx_t))) tail_r <- mkCReg(2,0);
    //Array#(Reg#(Bool)) full_r <- mkCReg(2, False);
    Ehr#(2, Bool) full_r <- mkEhr(False);
    Vector#(size, Reg#(t)) internal_store <- replicateM(mkRegU());

    //find out how many slots are full
    function UInt#(fill_state_t) full_slots(Integer i);
        UInt#(fill_state_t) result;

        //calculate from head and tail pointers
        if (head_r > tail_r[i]) result = extend(head_r) - extend(tail_r[i]);
        else if (tail_r[i] > head_r) result = fromInteger(valueOf(size)) - extend(tail_r[i]) + extend(head_r);
        // if both pointers are equal, must be full or empty
        else if (full_r[i]) result = fromInteger(valueOf(size));
        else result = 0;

        return result;
    endfunction

    method Action enq(UInt#(max_in_idx) count, Vector#(max_in, t) data);
        UInt#(idx_t) tmp = truncate_index(head_r, extend(count));
        head_r <= tmp;
        if(tail_r[1] == tmp) full_r[1] <= True;
        for(Integer i = 0; i < valueOf(max_in); i=i+1) begin
            if(fromInteger(i)<count) begin
                internal_store[truncate_index(head_r, fromInteger(i))] <= data[i];
            end
        end
    endmethod

    method Vector#(max_out, t) first;
        Vector#(max_out, t) result;
        for(Integer i = 0; i < valueOf(max_out); i=i+1)
            result[i] = internal_store[truncate_index(tail_r[0], fromInteger(i))];
        return result;
    endmethod

    method Action deq(UInt#(max_out_idx) count);
        if(count > 0) full_r[0] <= False;
        tail_r[0] <= truncate_index(tail_r[0], extend(count));
    endmethod

    method Bool enqReady = (full_slots(1) < fromInteger(valueOf(size)));
    method Bool enqReadyN(UInt#(max_in_idx) count) = (fromInteger(valueOf(size)) - full_slots(1) >= extend(count));
    method Bool deqReady = (full_slots(0) > 0);
    method Bool deqReadyN(UInt#(max_out_idx) count) = (full_slots(0) >= extend(count));
    method UInt#(fill_state_t) count = full_slots(0);


endmodule


endpackage: ESAMIMO
