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
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) misa <- replicateM(mkEhr( { 2'h1, 'b1000100000001 } )); //upper two bits: 32 Bit XLEN, lower bits: ISA ext in alphabetic
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mtvec <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mepc <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mstatus <- replicateM(mkEhr( (3<<11)|(1<<7) ));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mscratch <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mtval <- replicateM(mkEhr(0));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) mhartid <- replicateM(mkEhr(?));
    Vector#(NUM_THREADS, Ehr#(issuewidth_pad_t, Bit#(XLEN))) dummy_csr <- replicateM(mkEhr(0));

    // buffer for read responses
    Reg#(Maybe#(Bit#(XLEN))) read_resp <- mkRegU();

    // select correct CSR via index for rd and wr
    // return Invalid if not available
    function Maybe#(Ehr#(issuewidth_pad_t, Bit#(XLEN))) get_csr_rd(Bit#(12) addr, UInt#(thread_idx_t) thread_id);
        return case (addr)
            'h342: tagged Valid mcause[thread_id];
            'h301: tagged Valid misa[thread_id];
            'h304: tagged Valid mie[thread_id];
            'h305: tagged Valid mtvec[thread_id];
            'h341: tagged Valid mepc[thread_id];
            'h340: tagged Valid mscratch[thread_id];
            'h300: tagged Valid mstatus[thread_id];
            'h343: tagged Valid mtval[thread_id];
            'hf14: tagged Valid mhartid[thread_id];
            'h3b0, 'h3ae: tagged Valid dummy_csr[thread_id];
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
            'h342: tagged Valid mcause[thread_id];
            'h3b0, 'h3ae: tagged Valid dummy_csr[thread_id];
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
                    read_resp <= (tagged Valid r[valueOf(ISSUEWIDTH)]);
                    dbg_print(CSRFile, $format("reading %x from %x", r[valueOf(ISSUEWIDTH)], req.addr));
                end else
                    read_resp <= (tagged Invalid);
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Maybe#(Bit#(XLEN))) get();
                return read_resp;
            endmethod
        endinterface
    endinterface

    // write implementation - disambiguated by EHRs for multi-issue
    interface Put writes;
        method Action put(Vector#(ISSUEWIDTH, Maybe#(CsrWrite)) requests);
            action
                for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                    if(requests[i] matches tagged Valid .req) begin
                        let ehr_maybe = get_csr_wr(req.addr, req.thread_id);
                        if (ehr_maybe matches tagged Valid .r) begin
                            Bit#(XLEN) wr_data = req.data;
                            if (req.addr == 'h300) begin
                                let current_mstatus = r[i];
                                wr_data = {1'b0, req.data[30:23], 0, 2'b11, req.data[10:9], 1'b0, /*current_mstatus[7]*/ 1'b1, req.data[6], 2'b0, req.data[3:2], 2'b00};
                            end
                            r[i] <= wr_data;
                            dbg_print(CSRFile, $format("writing %x to %x", req.data, req.addr));
                        end
                    end
                end
            endaction
        endmethod
    endinterface

    // output current trap vector and return address to commit
    method Vector#(NUM_THREADS, Tuple2#(Bit#(XLEN), Bit#(XLEN))) trap_vectors(); 
        Vector#(NUM_THREADS, Tuple2#(Bit#(XLEN), Bit#(XLEN))) out;
        for (Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
            out[i] = tuple2(mtvec[i][0], mepc[i][0]);
        return out;
    endmethod
    
    // output current interrupt bits to commit
    method Vector#(NUM_THREADS, Bit#(3)) ext_interrupt_mask();
        Vector#(NUM_THREADS, Bit#(3)) out;
        for (Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
            out[i] = {mie[i][0][3], mie[i][0][7], mie[i][0][11]};
        return out;
    endmethod

    // input from commit if trap was taken - update related registers
    method Action write_int_data(Vector#(NUM_THREADS, Maybe#(TrapDescription)) in);
        for (Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
            if (in[i] matches tagged Valid .v) begin
                mcause[i][valueOf(ISSUEWIDTH)] <= v.cause;
                mepc[i][valueOf(ISSUEWIDTH)] <= v.pc;
                // we do not provide MTVAL feature, therefore it is set to 0
                // we still need this reg to avoid fault loops
                if (unpack(truncate(v.cause)) == MISALIGNED_LOAD || unpack(truncate(v.cause)) == AMO_ST_MISALIGNED) mtval[i][valueOf(ISSUEWIDTH)] <= v.val;

                let mstatus_loc = mstatus[i][valueOf(ISSUEWIDTH)];
                // save old interrupt ena
                mstatus_loc[7] = mstatus_loc[3];
                mstatus_loc[3] = 0;
                mstatus_loc[12:11] = 3;
                mstatus[i][valueOf(ISSUEWIDTH)] <= mstatus_loc;
            end
    endmethod

    method Action hart_id(Bit#(TLog#(TMul#(NUM_CPU, NUM_THREADS))) in);
        for (Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
            mhartid[i][valueOf(ISSUEWIDTH)] <= extend(in) + fromInteger(i);
    endmethod


endmodule

endpackage
