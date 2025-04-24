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
import ArianeRegFile::*;

// LATCH-based implementation - smaller footprint
// just re-wraps the imported verilog reg file in the correct interface
// and instantiates one per thread

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkRegFileAriane(RegFileIFC) provisos (
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t)
);

    // stateful registers
    // import verilog implementation
    Vector#(NUM_THREADS, ArianeRegFileIfc#(TMul#(2, ISSUEWIDTH), ISSUEWIDTH, Bit#(32))) regfile <- replicateM(mkArianeRegFile());

    // buffer for read requests
    Wire#(Vector#(TMul#(2, ISSUEWIDTH), UInt#(TLog#(NUM_THREADS)))) tid_bypass <- mkBypassWire();


    //writing to registers - needs no response
    method Action write(Vector#(ISSUEWIDTH, Maybe#(RegWrite)) requests);
        action
            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                // if the request is valid, write to the file
                if(requests[i] matches tagged Valid .req) begin
                    regfile[req.thread_id].wr[i].request(req.addr, req.data);
                end
            end
        endaction

    endmethod

    // server for register reading
    interface Server read_registers;
        interface Put request;
            method Action put(Vector#(TMul#(2, ISSUEWIDTH), RegRead) req);
                Vector#(TMul#(2, ISSUEWIDTH), UInt#(TLog#(NUM_THREADS))) tids = ?;

                // start request
                for (Integer i = 0; i < valueOf(ISSUEWIDTH)*2; i=i+1) begin
                    regfile[req[i].thread_id].rd[i].request(req[i].addr);
                    tids[i] = req[i].thread_id;
                end

                tid_bypass <= tids;
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) get();
                actionvalue
                    Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN)) response;

                    // get result
                    for (Integer i = 0; i < valueOf(ISSUEWIDTH)*2; i=i+1) begin
                        response[i] = regfile[tid_bypass[i]].rd[i].response();
                    end

                    return response;
                endactionvalue
            endmethod
        endinterface
    endinterface

endmodule


// FLIPFLOP based implementation

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkRegFile(RegFileIFC) provisos (
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t)
);

    // stateful registers
    // we do not need reg0, as it is hardwired to 0 (see RISC-V specificaton)
    Vector#(NUM_THREADS, Vector#(31, Ehr#(issuewidth_pad_t, Bit#(XLEN)))) regs <- replicateM(replicateM(mkEhr(?)));

    // buffer for read requests
    Wire#(Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) register_responses_w <- mkWire();

    // print the whole register file for debugging
    rule print_debug;
        for(Integer i = 0; i < 31; i=i+1)
            dbg_print(Regs, $format(i+1, ": ", regs[0][i][0]));
    endrule

    //writing to registers
    method Action write(Vector#(ISSUEWIDTH, Maybe#(RegWrite)) requests);
        action
            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                // if the request is valid, write to the file
                if(requests[i] matches tagged Valid .req &&& req.addr != 0) begin
                    regs[req.thread_id][req.addr - 1][i] <= req.data;
                end
            end
        endaction

    endmethod

    // server for register reading
    interface Server read_registers;
        interface Put request;
            method Action put(Vector#(TMul#(2, ISSUEWIDTH), RegRead) req);
                Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN)) response;

                // gather read results and forward them to the read interface
                for (Integer i = 0; i < valueOf(ISSUEWIDTH)*2; i=i+1) begin
                    let reg_addr = req[i].addr;
                    let thread_id = req[i].thread_id;
                    response[i] = regs[thread_id][reg_addr-1][0];
                end

                register_responses_w <= response;
            endmethod
        endinterface

        // return responses from the response wire
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