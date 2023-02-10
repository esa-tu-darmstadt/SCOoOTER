package CSRFile;

import Ehr::*;
import Vector::*;
import Interfaces::*;
import Types::*;
import Inst_Types::*;
import GetPut::*;
import ClientServer::*;
import FIFO::*;
import SpecialFIFOs::*;

module mkCSRFile(CsrFileIFC) provisos (
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t)
);

    Ehr#(issuewidth_pad_t, Bit#(XLEN)) mcause <- mkEhr(0);
    Ehr#(issuewidth_pad_t, Bit#(XLEN)) mie <- mkEhr(0);
    Ehr#(issuewidth_pad_t, Bit#(XLEN)) mtvec <- mkEhr(0);
    Ehr#(issuewidth_pad_t, Bit#(XLEN)) mepc <- mkEhr(0);

    function Maybe#(Ehr#(issuewidth_pad_t, Bit#(XLEN))) get_csr_rd(Bit#(12) addr);
        return case (addr)
            'h342: tagged Valid mcause;
            'h304: tagged Valid mie;
            'h305: tagged Valid mtvec;
            'h341: tagged Valid mepc;
            default: tagged Invalid;
        endcase;
    endfunction

    function Maybe#(Ehr#(issuewidth_pad_t, Bit#(XLEN))) get_csr_wr(Bit#(12) addr);
        return case (addr)
            'h304: tagged Valid mie;
            'h305: tagged Valid mtvec;
            'h341: tagged Valid mepc;
            default: tagged Invalid;
        endcase;
    endfunction

    FIFO#(Maybe#(Bit#(XLEN))) read_resp <- mkPipelineFIFO();

    interface Server read;
        interface Put request;
            method Action put(Bit#(12) addr);
                let ehr_maybe = get_csr_rd(addr);
            if (ehr_maybe matches tagged Valid .r) begin
                read_resp.enq(tagged Valid r[0]);
            end else
                read_resp.enq(tagged Invalid);
            endmethod
        endinterface
        interface Get response = toGet(read_resp);
    endinterface

    interface Put writes;
        method Action put(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(CsrWrite)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1)))) requests);
            action
                for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                    if(tpl_1(requests)[i] matches tagged Valid .req &&& fromInteger(i) < tpl_2(requests)) begin
                        let ehr_maybe = get_csr_wr(req.addr);
                        if (ehr_maybe matches tagged Valid .r) begin
                            r[i] <= req.data;
                        end
                    end
                end
            endaction
        endmethod
    endinterface

    method Tuple2#(Bit#(XLEN), Bit#(XLEN)) trap_vectors() = tuple2(mtvec[0], mepc[0]);
    method Action write_int_data(Bit#(XLEN) cause, Bit#(XLEN) pc);
        mcause[valueOf(ISSUEWIDTH)] <= cause;
        mepc[valueOf(ISSUEWIDTH)] <= pc;
    endmethod

    // SW, TI, EX
    method Bit#(3) ext_interrupt_mask() = {mie[0][3], mie[0][7], mie[0][11]};
endmodule

endpackage