package RVFITracer;

import Vector::*;
import Types::*;
import Inst_Types::*;

interface RVFITraceIFC;
method Action rvfi_in(Vector#(ISSUEWIDTH, RVFIBus) rvfi);
endinterface


module mkRVFITracer(RVFITraceIFC);

    UInt#(XLEN) tohost_addr = 32'h10000;

    Vector#(NUM_THREADS, Reg#(File)) out_log <- replicateM(mkRegU());
    
    Reg#(Bool) opened <- mkReg(False);
    rule open_files (!opened);
        opened <= True;
        for(Integer i = 0; i<valueOf(NUM_THREADS); i=i+1) begin
            let out_log_loc <- $fopen("trace_rvfi_hart_" + (i<10?"0":"") + integerToString(i) + ".dasm", "w");
            out_log[i] <= out_log_loc;
        end

        if (tohost_addr == 0) begin
            $display("*** [rvf_tracer] WARNING: No valid address of 'tohost' (tohost == 0x%h)\n", tohost_addr);
        end
    endrule
    

    method Action rvfi_in(Vector#(ISSUEWIDTH, RVFIBus) rvfi);

        for(Integer i = 0; i<valueOf(NUM_THREADS);i=i+1) begin
            if(rvfi[i].valid) begin
                let log = out_log[rvfi[i].thread_id]; 
                //TODO: core numbers
                $fwrite(log, "core   0: 0x%h (0x%h) DASM(%h)\n", rvfi[i].pc_rdata, rvfi[i].insn, rvfi[i].insn);

                // misc. inst info
                $fwrite(log, "%h 0x%h (0x%h)", rvfi[i].mode, rvfi[i].pc_rdata, rvfi[i].insn);

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
                        $finish(0);
                    end
                end
                $fwrite(log, "\n");

                // TODO: trace exceptions
            end
        end

    endmethod

endmodule

endpackage