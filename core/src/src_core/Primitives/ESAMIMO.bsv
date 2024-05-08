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
import TestFunctions     ::*;
import BUtils            ::*;

////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////

interface IWinIfc#(numeric type max_in, numeric type max_out, numeric type size, type t);

    method Action enq(UInt#(TLog#(TAdd#(max_in, 1))) count, Vector#(max_in, t) data);

    method Vector#(max_out, t) first;

    method Action deq(UInt#(TLog#(TAdd#(max_out, 1))) count);

    method Bool enqReady;
    method Bool enqReadyN(UInt#(TLog#(TAdd#(max_in, 1))) count);
    method Bool deqReady;
    method Bool deqReadyN(UInt#(TLog#(TAdd#(max_out, 1))) count);
    method UInt#(TLog#(TAdd#(size, 1))) count;
    method Bit#(max_out) deqReadyMask;

    method Action deqByMask(Bit#(max_out) mask);

endinterface

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkESAMIMO_banks(IWinIfc#(max_in, max_out, size, t)) provisos (
    Bits#(t, st),              // object must have bit representation
    Log#(size, idx_t),

    Add#(d__, 1, size),

    Add#(a__, max_out_idx, fill_state_t),
    Add#(b__, max_in_idx, fill_state_t),
    Add#(c__, idx_t, fill_state_t),
    Add#(max_in, 0, max_out), // must be equal
    Div#(size, max_in, bank_size),
    Add#(max_in, 0, bank_amt),

    // needed for compatibility with the vanilla MIMO interface
    Log#(TAdd#(size, 1), fill_state_t),
    Log#(TAdd#(max_in, 1), max_in_idx),
    Log#(TAdd#(max_out, 1), max_out_idx),
    Log#(TAdd#(1, bank_amt), max_in_idx),
    Log#(TAdd#(1, bank_amt), max_out_idx),

    Log#(max_in, bank_idx_t),

    FShow#(Vector::Vector#(max_in, t)),

    Add#(e__, fill_state_t, TAdd#(1, idx_t))
);

    // needed as input for truncated add function
    // such that the ISSUEWIDTH is transported to the function
    // this variable is never used
    Bit#(bank_amt) dummy = 0;

    // generate banks
    Vector#(bank_amt, FIFOF#(t)) banks <- replicateM(mkUGSizedFIFOF(valueOf(bank_size)));

    // track which bank has next enq/deq operation
    Reg#(UInt#(bank_idx_t)) head_bank_r <- mkReg(0);
    Reg#(UInt#(bank_idx_t)) tail_bank_r <- mkReg(0);

    // helper functions to extract signals from a bank
    function Bool get_rdy_enq(FIFOF#(t) ff) = ff.notFull();
    function Bool get_rdy_deq(FIFOF#(t) ff) = ff.notEmpty();
    function t get_entry(FIFOF#(t) ff) = ff.first();

    method Action enq(UInt#(max_in_idx) count, Vector#(max_in, t) data);
        let enq_data = rotateBy(data, head_bank_r);

        function Bool should_fire(Integer i) = fromInteger(i) < count;
        Vector#(bank_amt, Bool) enq_fire = rotateBy(genWith(should_fire), head_bank_r);

        for(Integer i = 0; i < valueOf(bank_amt); i=i+1)
            if (enq_fire[i]) banks[i].enq(enq_data[i]);

        head_bank_r <= rollover_add(dummy, head_bank_r, cExtend(count));
    endmethod

    method Vector#(max_out, t) first;
        return rotateBy(map(get_entry, banks), truncate(fromInteger(valueOf(bank_amt)) - unpack({1'b0, pack(tail_bank_r)})));
    endmethod

    method Action deq(UInt#(max_out_idx) count);
        for(Integer i = 0; i < valueOf(bank_amt); i=i+1)
            if (fromInteger(i) < count)
                banks[rollover_add(dummy, tail_bank_r, fromInteger(i))].deq();
        
        tail_bank_r <= rollover_add(dummy, tail_bank_r, cExtend(count));
    endmethod

    method Action deqByMask(Bit#(max_out) mask);
        Vector#(bank_amt, Bool) mask_rot = rotateBy(unpack(mask), tail_bank_r);

        for(Integer i = 0; i < valueOf(bank_amt); i=i+1)
            if (mask_rot[i])
                banks[i].deq();
        
        tail_bank_r <= rollover_add(dummy, tail_bank_r, cExtend(Vector::countElem(True, unpack(mask))));
    endmethod

    method Bool enqReady = (countElem(True, map(get_rdy_enq, banks)) > 0);
    method Bool enqReadyN(UInt#(max_in_idx) count) = (countElem(True, map(get_rdy_enq, banks)) >= count);
    method Bool deqReady = (countElem(True, map(get_rdy_deq, banks)) > 0);
    method Bool deqReadyN(UInt#(max_out_idx) count) = (countElem(True, map(get_rdy_deq, banks)) >= count);
    method UInt#(fill_state_t) count = extend(countElem(True, map(get_rdy_deq, banks)));

    method Bit#(max_out) deqReadyMask() = pack(rotateBy(map(get_rdy_deq, banks), truncate(fromInteger(valueOf(bank_amt)) - unpack({1'b0, pack(tail_bank_r)}))));
endmodule


endpackage: ESAMIMO
