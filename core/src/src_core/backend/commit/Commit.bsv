package Commit;

import Debug::*;
import Types::*;
import Vector::*;
import Inst_Types::*;
import Interfaces::*;
import FIFO::*;
import SpecialFIFOs::*;
import BlueAXI::*;
import Connectable::*;
import GetPut::*;

(* synthesize *)
module mkCommit(CommitIFC) provisos(
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);

FIFO#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) out_buffer <- mkPipelineFIFO();

Reg#(UInt#(XLEN)) epoch <- mkReg(0);

Wire#(Bit#(XLEN)) redirect_pc_w <- mkWire();

FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) memory_rq_out <- mkBypassFIFO();

function Maybe#(MemWr) rob_entry_to_memory_write(RobEntry re) = re.epoch == epoch &&& re.mem_wr matches tagged Valid .v ? tagged Valid v : tagged Invalid; 

function Bool check_entry_for_mem_access(RobEntry entry) = (entry.mem_wr matches tagged Valid .v ? True : False);
method ActionValue#(UInt#(issuewidth_log_t)) consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(issuewidth_log_t) count);
    actionvalue
        //$display("commit ", fshow(instructions), " ", fshow(count));
        Vector#(ISSUEWIDTH, Maybe#(RegWrite)) temp_requests = replicate(tagged Invalid);

        Bool done = False;

        //only for bodge
        UInt#(issuewidth_log_t) count_committed = count;

        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            if(instructions[i].epoch == epoch) begin
                // write registers
                if(fromInteger(i) < count &&& 
                   instructions[i].result matches tagged Result .r &&& 
                   !done) begin
                    dbg_print(Commit, $format(fshow(instructions[i])));
                    temp_requests[i] = tagged Valid RegWrite {addr: instructions[i].destination, data: r};
                end

                // check branch
                if(fromInteger(i) < count && instructions[i].next_pc != instructions[i].pred_pc && !done) begin
                    epoch <= epoch + 1;
                    // generate mispredict signal for IFU
                    redirect_pc_w <= instructions[i].next_pc;
                    done = True;
                    count_committed = fromInteger(i);
                end

            end

            
        end

        out_buffer.enq(temp_requests);

        // memory write
        let writes = Vector::map(rob_entry_to_memory_write, instructions);
        memory_rq_out.enq(tuple2(writes, count_committed));

        return count;
    endactionvalue
endmethod

interface Get memory_writes;
    method ActionValue#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) get();
        actionvalue
            memory_rq_out.deq();
            return memory_rq_out.first();
        endactionvalue
    endmethod
endinterface

method Bit#(XLEN) redirect_pc();
    return redirect_pc_w;
endmethod

method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    actionvalue
        out_buffer.deq();
        return out_buffer.first();
    endactionvalue
endmethod

endmodule

endpackage