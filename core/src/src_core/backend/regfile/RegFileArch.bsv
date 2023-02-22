package RegFileArch;

// this register file tracks the ARCHITECTURAL registers
// speculative updates are tracked by RegFileEvo

import Types::*;
import Vector::*;
import Inst_Types::*;
import Interfaces::*;
import Debug::*;
import Ehr::*;

(* synthesize *)
module mkRegFile(RegFileIFC) provisos (
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t)
);

    // stateful registers
    Vector#(31, Ehr#(issuewidth_pad_t, Bit#(XLEN))) regs <- replicateM(mkEhr(?));

    // helper function for reading ehr registers (returns value from port 0)
    function Bit#(XLEN) get_ehr_read(Ehr#(issuewidth_pad_t, Bit#(XLEN)) e) = e[valueOf(ISSUEWIDTH)];

    // print the whole register file for debugging
    rule print_debug;
        for(Integer i = 0; i < 31; i=i+1)
            dbg_print(Regs, $format(i+1, ": ", regs[i][0]));
    endrule

    //writing to registers
    method Action write(Vector#(ISSUEWIDTH, Maybe#(RegWrite)) requests);
        action
            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                // if the request is valid, write to the file
                if(requests[i] matches tagged Valid .req &&& req.addr != 0) begin
                    regs[req.addr - 1][i] <= req.data;
                end
            end
        endaction

    endmethod

    // return the entire reg file
    method Vector#(31, Bit#(XLEN)) values();
        return Vector::map(get_ehr_read, regs);
    endmethod

endmodule


endpackage