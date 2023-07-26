package ShiftBuffer;

// Notes :
// - This module delays signals by n cycles

////////////////////////////////////////////////////////////////////////////////
/// Imports
////////////////////////////////////////////////////////////////////////////////
import Vector            ::*;

interface ShiftBufferIfc#(numeric type n, type t);
    interface Reg#(t) r;
endinterface



module mkShiftBuffer#(t init)(ShiftBufferIfc#(n, t)) provisos (
    Bits#(t, st)              // object must have bit representation
);

    Vector#(n, Reg#(t)) storage <- replicateM(mkReg(init));
    Reg#(t) bypass <- mkBypassWire();
    Vector#(TAdd#(n,1), Reg#(t)) full_store = Vector::cons(bypass, storage);

    rule propagate;
        for(Integer i = 0; i < valueOf(n); i=i+1)
            full_store[i+1]._write(full_store[i]._read());
    endrule
    interface Reg r;
        interface _read = Vector::last(full_store)._read;
        interface _write = full_store[0]._write;
    endinterface
endmodule

endpackage: ShiftBuffer
