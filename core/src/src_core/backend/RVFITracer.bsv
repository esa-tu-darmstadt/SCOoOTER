package RVFITracer;

/*

Write RVFI information to a trace file for Core-V-Verif.

*/

import Vector::*;
import Types::*;
import Inst_Types::*;


// interface just gets the trace info
interface RVFITraceIFC;
    method Action rvfi_in(Vector#(ISSUEWIDTH, RVFIBus) rvfi);
endinterface


module mkRVFITracer(RVFITraceIFC);

    // addr to which tests write on completion
    UInt#(XLEN) tohost_addr = `TOHOST;

    // one log per thread
    Vector#(NUM_THREADS, Reg#(File)) out_log <- replicateM(mkRegU());
    
    // open log files for writing
    // one log file per HART is generated
    Reg#(Bool) opened <- mkReg(False);
    rule open_files (!opened);
        opened <= True;
        for(Integer i = 0; i<valueOf(NUM_THREADS); i=i+1) begin
            let out_log_loc <- $fopen("trace_rvfi_hart_" + (i<10?"0":"") + integerToString(i) + ".dasm", "w");
            out_log[i] <= out_log_loc;
        end

        // warn if tohost is not set
        if (tohost_addr == 0) begin
            $display("*** [rvf_tracer] WARNING: No valid address of 'tohost' (tohost == 0x%h)\n", tohost_addr);
        end
        $display("TOHOST: ", `TOHOST);
    endrule
    

    // consume trace info
    method Action rvfi_in(Vector#(ISSUEWIDTH, RVFIBus) rvfi);

        for(Integer i = 0; i<valueOf(ISSUEWIDTH);i=i+1) begin
            if(rvfi[i].valid) begin
                Bit#(32) pc_long = zeroExtend(rvfi[i].pc_rdata);
                let log = out_log[rvfi[i].thread_id]; 
                // TODO: core numbers
                // currently, only single-core is supported
                $fwrite(log, "core   0: 0x%h (0x%h) DASM(%h)\n", pc_long, rvfi[i].insn, rvfi[i].insn);

                // misc. inst info
                $fwrite(log, "%h 0x%h (0x%h)", rvfi[i].mode, pc_long, rvfi[i].insn);

                // reg write if applicable
                if(rvfi[i].rd1_addr != 0)
                    $fwrite(log, " x%d 0x%h", rvfi[i].rd1_addr, rvfi[i].rd1_wdata);

                // memory reads
                if (rvfi[i].mem_rmask != 0) begin
                    $fwrite(log, " mem 0x%h", rvfi[i].mem_addr);
                end

                // stop generation if write to end addr
                if (rvfi[i].mem_wmask != 0) begin
                    $fwrite(log, " mem 0x%h 0x%h", rvfi[i].mem_addr, rvfi[i].mem_wdata);
                    if (tohost_addr != 0 &&
                        rvfi[i].mem_addr == tohost_addr &&
                        rvfi[i].mem_wdata[0] == 1'b1) begin
                        $finish();
                    end
                end
                $fwrite(log, "\n");
            end
        end

    endmethod

endmodule

endpackage