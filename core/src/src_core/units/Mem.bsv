package Mem;

import Interfaces::*;
import Types::*;
import Inst_Types::*;
import FIFO::*;
import SpecialFIFOs::*;
import RWire::*;
import Debug::*;

(* synthesize *)
module mkMem(FunctionalUnitIFC);

FIFO#(Instruction) in <- mkPipelineFIFO();
FIFO#(Result) out <- mkPipelineFIFO();
RWire#(Result) out_valid <- mkRWire();

rule calculate;
    let inst = in.first(); in.deq();

    out.enq(Result {result : tagged Result 0, new_pc : tagged Invalid, tag : inst.tag});
endrule

rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);

endrule

method Action put(Instruction inst);
    in.enq(inst);
endmethod

method Maybe#(Result) get() =
    out_valid.wget();
endmodule

endpackage