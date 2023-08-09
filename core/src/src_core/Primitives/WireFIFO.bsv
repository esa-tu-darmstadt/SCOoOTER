package WireFIFO;

// Notes :
// - This module delays signals by n cycles

////////////////////////////////////////////////////////////////////////////////
/// Imports
////////////////////////////////////////////////////////////////////////////////
import FIFO            ::*;
import FIFOF::*;


module mkWireFIFO(FIFO#(t)) provisos (
    Bits#(t, st)              // object must have bit representation
);

    Wire#(t) w <- mkWire();

    method Action deq();
    endmethod
    method Action enq(t a) = w._write(a);
    method t first() = w._read();
endmodule

module mkWireFIFOF(FIFOF#(t)) provisos (
    Bits#(t, st)              // object must have bit representation
);

    Wire#(t) w <- mkWire();

    method Action deq();
    endmethod
    method Action enq(t a) = w._write(a);
    method t first() = w._read();
    method Bool notEmpty() = True;
    method Bool notFull() = True;
endmodule

endpackage: WireFIFO
