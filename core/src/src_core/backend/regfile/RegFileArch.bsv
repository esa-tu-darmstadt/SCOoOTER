package RegFileArch;

// this register file tracks the ARCHITECTURAL registers
// speculative updates are tracked by RegFileEvo

import Types::*;
import Vector::*;
import Inst_Types::*;
import Interfaces::*;
import Debug::*;
import Ehr::*;
import ClientServer::*;
import GetPut::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkRegFile(RegFileIFC) provisos (
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t)
);

    // stateful registers
    // we do not need reg0, as this is hardwired to 0
    Vector#(31, Ehr#(issuewidth_pad_t, Bit#(XLEN))) regs <- replicateM(mkEhr(?));

    // buffer for read requests
    Wire#(Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) register_responses_w <- mkWire();

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

    // server for register reading
    interface Server read_registers;
        interface Put request;
            method Action put(Vector#(TMul#(2, ISSUEWIDTH), RADDR) req);
                Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN)) response;

                for (Integer i = 0; i < valueOf(ISSUEWIDTH)*2; i=i+1) begin
                    let reg_addr = req[i];
                    response[i] = regs[reg_addr-1][0];
                end

                register_responses_w <= response;
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) get();
                actionvalue
                    return register_responses_w;
                endactionvalue
            endmethod
        endinterface
    endinterface

endmodule


endpackage