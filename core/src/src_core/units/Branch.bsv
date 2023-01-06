package Branch;

import Interfaces::*;
import Types::*;
import Inst_Types::*;
import FIFO::*;
import SpecialFIFOs::*;
import RWire::*;
import Debug::*;

(* synthesize *)
module mkBranch(FunctionalUnitIFC);

method Action put(Instruction inst);
    dbg_print(BRU, $format("got instruction: ", fshow(inst)));
endmethod

endmodule

endpackage