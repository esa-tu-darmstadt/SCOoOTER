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
    Add#(__f, 1, st),          // object is at least 1 byte in size
	Add#(2, __a, size),        // must have at least 2 elements of storage
	Add#(__b, max_in, size),   // the max enqueued amount must be less than or equal to the full storage
	Add#(__c, max_out, size),  // the max dequeued amount must be less than or equal to the full storage
    Mul#(st, size, total),     // total bits of storage
    Mul#(st, max_in, intot),   // total bits to be enqueued
    Mul#(st, max_out, outtot), // total bits to be dequeued
    Add#(__d, outtot, total),  // make sure the number of dequeue bits is not larger than the total storage
	Max#(max_in, max_out, max),// calculate the max width of the memories
	Div#(size, max, em1),      // calculate the number of entries for each memory required
	Add#(em1, 1, e),
	Add#(__e, max_out, max),
    Log#(size, idx_t),
    Add#(1, size, size_pad),
    Log#(size_pad, fill_state_t),
    Add#(1, max_out, max_out_p),
    Log#(max_out_p, max_out_idx),
    Add#(1, max_in, max_in_p),
    Log#(max_in_p, max_in_idx),

    Add#(a__, max_out_idx, fill_state_t),
    Add#(b__, max_in_idx, fill_state_t),

    // needed for compatibility with the vanilla MIMO interface
    Log#(TAdd#(size, 1), fill_state_t),
    Log#(TAdd#(max_in, 1), max_in_idx),
    Log#(TAdd#(max_out, 1), max_in_idx),
  
    Add#(c__, max_in_idx, fill_state_t),
    Add#(d__, idx_t, fill_state_t),

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
