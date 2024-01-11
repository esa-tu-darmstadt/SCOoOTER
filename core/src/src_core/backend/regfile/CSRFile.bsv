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
import ArianeEhr::*;

module mkCSRFile(CsrFileIFC) provisos (
    Log#(NUM_CPU, cpu_idx_t),
    Log#(NUM_THREADS, thread_idx_t)
);

    // select latch or flip-flop based implementation
    let ehrModal = (valueOf(REGCSR_LATCH_BASED) == 0 ? mkEhr : mkArianeEhr);

    // register implementations
    // one port per issue slot and one extra port for updates from hw
    Vector#(NUM_THREADS, Ehr#(2, Bit#(XLEN))) mcause <- replicateM(ehrModal(0));
    Vector#(NUM_THREADS, Ehr#(2, Bit#(XLEN))) mie <- replicateM(ehrModal(0));
    Vector#(NUM_THREADS, Ehr#(2, Bit#(XLEN))) misa <- replicateM(ehrModal( { 2'h1, 'b1000100000001 } )); //upper two bits: 32 Bit XLEN, lower bits: ISA ext in alphabetic
    Vector#(NUM_THREADS, Ehr#(2, Bit#(XLEN))) mtvec <- replicateM(ehrModal(0));
    Vector#(NUM_THREADS, Ehr#(2, Bit#(XLEN))) mepc <- replicateM(ehrModal(0));
    Vector#(NUM_THREADS, Ehr#(2, Bit#(XLEN))) mstatus <- replicateM(ehrModal( (3<<11)|(1<<7) ));
    Vector#(NUM_THREADS, Ehr#(2, Bit#(XLEN))) mscratch <- replicateM(ehrModal(0));
    Vector#(NUM_THREADS, Ehr#(2, Bit#(XLEN))) mtval <- replicateM(ehrModal(0));
    Vector#(NUM_THREADS, Ehr#(2, Bit#(XLEN))) mhartid <- replicateM(ehrModal(?));

    // buffer for read responses
    Reg#(Maybe#(Bit#(XLEN))) read_resp <- mkRegU();

    // select correct CSR via index for rd and wr
    // return Invalid if not available
    function Maybe#(Ehr#(2, Bit#(XLEN))) get_csr_rd(Bit#(12) addr, UInt#(thread_idx_t) thread_id);
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
            default: tagged Invalid;
        endcase;
    endfunction
    function Maybe#(Ehr#(2, Bit#(XLEN))) get_csr_wr(Bit#(12) addr, UInt#(thread_idx_t) thread_id);
        return case (addr)
            'h304: tagged Valid mie[thread_id];
            'h305: tagged Valid mtvec[thread_id];
            'h341: tagged Valid mepc[thread_id];
            'h300: tagged Valid mstatus[thread_id];
            'h340: tagged Valid mscratch[thread_id];
            'h343: tagged Valid mtval[thread_id];
            'h342: tagged Valid mcause[thread_id];
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
                    read_resp <= (tagged Valid r[0]);
                    dbg_print(CSRFile, $format("reading %x from %x", r[0], req.addr));
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
    interface Put write;
        method Action put(CsrWrite request);
            let ehr_maybe = get_csr_wr(request.addr, request.thread_id);
                if (ehr_maybe matches tagged Valid .r) begin
                
                    let current_value = r[0];

                    // do not write to disallowed fields
                    Bit#(XLEN) wr_data = case (request.addr)
                        'h300: {1'b0, request.data[30:23], 0, 2'b11, request.data[10:9], 1'b0, /*current_mstatus[7]*/ 1'b1, request.data[6], 2'b0, request.data[3:2], 2'b00};
                        'h304: {0, request.data[11], 3'b0, request.data[7], 3'b0, request.data[3], 3'b0};
                        'h341: {truncateLSB(request.data), 2'b00};
                        default: request.data;
                    endcase;

                    r[0] <= wr_data;
                    dbg_print(CSRFile, $format("writing %x to %x", request.data, request.addr));
                end
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
                mcause[i][1] <= v.cause;
                mepc[i][1] <= {v.pc, 2'b00};
                // we do not provide MTVAL feature, therefore it is set to 0
                // we still need this reg to avoid fault loops
                if (unpack(truncate(v.cause)) == MISALIGNED_LOAD || unpack(truncate(v.cause)) == AMO_ST_MISALIGNED) mtval[i][1] <= v.val;

                let mstatus_loc = mstatus[i][1];
                // save old interrupt ena
                mstatus_loc[7] = mstatus_loc[3];
                mstatus_loc[3] = 0;
                mstatus_loc[12:11] = 3;
                mstatus[i][1] <= mstatus_loc;
            end
    endmethod

    method Action hart_id(Bit#(TLog#(TMul#(NUM_CPU, NUM_THREADS))) in);
        for (Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
            mhartid[i][1] <= extend(in) + fromInteger(i);
    endmethod


endmodule

endpackage
