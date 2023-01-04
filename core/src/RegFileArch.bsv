package RegFileArch;

import Types::*;
import Vector::*;
import Inst_Types::*;
import Interfaces::*;
import Debug::*;

(* synthesize *)
module mkRegFile(RegFileIFC);

    //stateful registers
    Vector#(31, Reg#(Bit#(XLEN))) regs <- replicateM(mkRegU());

    rule print_debug;
        for(Integer i = 0; i < 31; i=i+1)
            dbg_print(Regs, $format(i+1, ": ", regs[i]));
    endrule

    //writing to register
    method Action write(Vector#(ISSUEWIDTH, Maybe#(RegWrite)) requests);
        action
            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                if(requests[i] matches tagged Valid .req &&& req.addr != 0) begin
                    regs[req.addr - 1] <= req.data;
                end
            end
        endaction
    endmethod

    method Vector#(31, Bit#(XLEN)) values();
        return Vector::readVReg(regs);
    endmethod

endmodule


endpackage