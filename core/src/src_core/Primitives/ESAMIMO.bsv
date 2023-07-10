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

////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////


module mkESAMIMO(MIMO#(max_in, max_out, size, t)) provisos (
    Bits#(t, st),              // object must have bit representation
    Log#(size, idx_t),

    Add#(a__, max_out_idx, fill_state_t),
    Add#(b__, max_in_idx, fill_state_t),
    Add#(c__, idx_t, fill_state_t),

    // needed for compatibility with the vanilla MIMO interface
    Log#(TAdd#(size, 1), fill_state_t),
    Log#(TAdd#(max_in, 1), max_in_idx),
    Log#(TAdd#(max_out, 1), max_out_idx),

    FShow#(Vector::Vector#(max_in, t))
);

    // fullness state
    Reg#(UInt#(idx_t)) head_r <- mkReg(0);
    Reg#(UInt#(idx_t)) tail_r <- mkReg(0);
    Array#(Reg#(Bool)) full_r <- mkCReg(2, False);
    Vector#(size, Reg#(t)) internal_store <- replicateM(mkRegU());

    //find out how many slots are full
    function UInt#(fill_state_t) full_slots;
        UInt#(fill_state_t) result;

        //calculate from head and tail pointers
        if (head_r > tail_r) result = extend(head_r) - extend(tail_r);
        else if (tail_r > head_r) result = fromInteger(valueOf(size)) - extend(tail_r) + extend(head_r);
        // if both pointers are equal, must be full or empty
        else if (full_r[0]) result = fromInteger(valueOf(size));
        else result = 0;

        return result;
    endfunction

    method Action enq(UInt#(max_in_idx) count, Vector#(max_in, t) data);
        UInt#(fill_state_t) tmp = extend(head_r) + extend(count);
        head_r <= truncate(tmp);
        if(tail_r == truncate(tmp)) full_r[0] <= True;
        for(Integer i = 0; i < valueOf(max_in); i=i+1) begin
            if(fromInteger(i)<count) begin
                internal_store[head_r + fromInteger(i)] <= data[i];
            end
        end
    endmethod

    method Vector#(max_out, t) first;
        Vector#(max_out, t) result;
        for(Integer i = 0; i < valueOf(max_out); i=i+1)
            result[i] = internal_store[tail_r + fromInteger(i)];
        return result;
    endmethod

    method Action deq(UInt#(max_out_idx) count);
        if(count > 0) full_r[1] <= False;
        UInt#(fill_state_t) tmp = extend(tail_r) + extend(count);
        tail_r <= truncate(tmp);
    endmethod

    method Bool enqReady = (full_slots() < fromInteger(valueOf(size)));
    method Bool enqReadyN(UInt#(max_in_idx) count) = (fromInteger(valueOf(size)) - full_slots() >= extend(count));
    method Bool deqReady = (full_slots() > 0);
    method Bool deqReadyN(UInt#(max_out_idx) count) = (full_slots() >= extend(count));
    method UInt#(fill_state_t) count = full_slots();


endmodule


endpackage: ESAMIMO
