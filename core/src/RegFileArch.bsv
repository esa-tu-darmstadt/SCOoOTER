package RegFileArch;

import Types::*;
import Vector::*;
import Inst_Types::*;
import Interfaces::*;
import Debug::*;
import ConfigReg::*;

(* synthesize *)
module mkRegFile(RegFileIFC);

    //stateful registers
    Vector#(31, Reg#(Bit#(XLEN))) regs <- replicateM(mkConfigRegU());

    rule print_debug;
        for(Integer i = 0; i < 31; i=i+1)
            dbg_print(Regs, $format(i+1, ": ", regs[i]));
    endrule

    //writing to register
    method Action write(Vector#(ISSUEWIDTH, Maybe#(RegWrite)) requests);
        Vector#(31, Bit#(XLEN)) regs_local = Vector::readVReg(regs);

        action
            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                if(requests[i] matches tagged Valid .req &&& req.addr != 0) begin
                    regs_local[req.addr - 1] = req.data;
                end
            end
        endaction

        Vector::writeVReg(regs, regs_local);
    endmethod

    method Vector#(31, Bit#(XLEN)) values();
        return Vector::readVReg(regs);
    endmethod

endmodule


endpackage