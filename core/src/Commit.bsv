package Commit;

import Debug::*;
import Types::*;
import Vector::*;
import Inst_Types::*;
import Interfaces::*;
import FIFO::*;
import SpecialFIFOs::*;

(* synthesize *)
module mkCommit(CommitIFC) provisos(
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);

FIFO#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) out_buffer <- mkPipelineFIFO();

Reg#(UInt#(XLEN)) epoch <- mkReg(0);

Wire#(Bit#(XLEN)) redirect_pc_w <- mkWire();

method ActionValue#(UInt#(issuewidth_log_t)) consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(issuewidth_log_t) count);
    actionvalue
        Vector#(ISSUEWIDTH, Maybe#(RegWrite)) temp_requests = replicate(tagged Invalid);

        Bool done = False;

        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            if(instructions[i].epoch == epoch) begin
                // write registers
                if(fromInteger(i) < count &&& instructions[i].result matches tagged Result .r &&& !done) begin
                    dbg_print(Commit, $format(fshow(instructions[i])));
                    temp_requests[i] = tagged Valid RegWrite {addr: instructions[i].destination, data: r};
                end

                // check branch
                if(fromInteger(i) < count && instructions[i].next_pc != instructions[i].pred_pc && !done) begin
                    epoch <= epoch + 1;
                    // generate mispredict signal for IFU
                    redirect_pc_w <= instructions[i].next_pc;
                    done = True;
                end
            end
        end

        out_buffer.enq(temp_requests);

        return count;
    endactionvalue
endmethod

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