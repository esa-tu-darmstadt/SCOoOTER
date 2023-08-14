package CSRFile;

/*
  This is the CSR register file.
*/

import Ehr::*;
import Vector::*;
import Interfaces::*;
import Types::*;
import Inst_Types::*;
import GetPut::*;
import ClientServer::*;
import FIFO::*;
import SpecialFIFOs::*;
import Debug::*;

module mkCSRFile(CsrFileIFC) provisos (
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(NUM_CPU, cpu_idx_t),
    Log#(NUM_THREADS, thread_idx_t)
);

    // register implementations
    // one port per issue slot and one extra port for updates from hw
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mcause <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mie <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mtvec <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mepc <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mstatus <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mscratch <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mtval <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mhartid <- replicateM(mkEhr(?));

    // buffer for read responses
    FIFO#(Maybe#(Bit#(XLEN))) read_resp <- mkPipelineFIFO();

    // select correct CSR via index for rd and wr
    // return Invalid if not available
    function Maybe#(Ehr#(issuewidth_pad_t, Bit#(XLEN))) get_csr_rd(Bit#(12) addr, UInt#(thread_idx_t) thread_id);
        return case (addr)
            'h342: tagged Valid mcause[thread_id];
            'h304: tagged Valid mie[thread_id];
            'h305: tagged Valid mtvec[thread_id];
            'h341: tagged Valid mepc[thread_id];
            'h340: tagged Valid mscratch[thread_id];
            'h300: tagged Valid mstatus[thread_id];
            'h343: tagged Valid mtval[thread_id];
            'hf14: tagged Valid mhartid[thread_id];
            default: tagged Invalid;
        endcase;
    endfunction
    function Maybe#(Ehr#(issuewidth_pad_t, Bit#(XLEN))) get_csr_wr(Bit#(12) addr, UInt#(thread_idx_t) thread_id);
        return case (addr)
            'h304: tagged Valid mie[thread_id];
            'h305: tagged Valid mtvec[thread_id];
            'h341: tagged Valid mepc[thread_id];
            'h300: tagged Valid mstatus[thread_id];
            'h340: tagged Valid mscratch[thread_id];
            'h343: tagged Valid mtval[thread_id];
            default: tagged Invalid;
        endcase;
    endfunction

    // read implementation
    interface Server read;
        interface Put request;
            method Action put(CsrRead req);
                // test if ehr exists and return value if it does
                // trap if it does not
                let ehr_maybe = get_csr_rd(req.addr, req.thread_id);
                if (ehr_maybe matches tagged Valid .r) begin
                    read_resp.enq(tagged Valid r[valueOf(ISSUEWIDTH)]);
                    dbg_print(CSRFile, $format("reading %x from %x", r[valueOf(ISSUEWIDTH)], req.addr));
                end else
                    read_resp.enq(tagged Invalid);
            endmethod
        endinterface
        interface Get response = toGet(read_resp);
    endinterface

    // write implementation - disambiguated by EHRs for multi-issue
    interface Put writes;
        method Action put(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(CsrWrite)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1)))) requests);
            action
                for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                    if(tpl_1(requests)[i] matches tagged Valid .req &&& fromInteger(i) < tpl_2(requests)) begin
                        let ehr_maybe = get_csr_wr(req.addr, req.thread_id);
                        if (ehr_maybe matches tagged Valid .r) begin
                            r[i] <= req.data;
                            dbg_print(CSRFile, $format("writing %x to %x", req.data, req.addr));
                        end
                    end
                end
            endaction
        endmethod
    endinterface

    // output current trap vector and return address to commit
    method Tuple2#(Bit#(XLEN), Bit#(XLEN)) trap_vectors() = tuple2(mtvec[0][0], mepc[0][0]);
    
    // output current interrupt bits to commit
    method Bit#(3) ext_interrupt_mask() = {mie[0][0][3], mie[0][0][7], mie[0][0][11]};

    // input from commit if trap was taken - update related registers
    method Action write_int_data(Bit#(XLEN) cause, Bit#(XLEN) pc);
        mcause[0][valueOf(ISSUEWIDTH)] <= cause;
        mepc[0][valueOf(ISSUEWIDTH)] <= pc;
        // we do not provide MTVAL feature, therefore it is set to 0
        // we still need this reg to avoid fault loops
        mtval[0][valueOf(ISSUEWIDTH)] <= 0;
    endmethod

    method Action hart_id(Bit#(TLog#(NUM_CPU)) in);
        mhartid[0][valueOf(ISSUEWIDTH)] <= extend(in);
    endmethod


endmodule

endpackage
