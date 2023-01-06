package Commit;

import Debug::*;
import Types::*;
import Vector::*;
import Inst_Types::*;
import Interfaces::*;
import FIFO::*;
import SpecialFIFOs::*;

module mkCommit(CommitIFC) provisos(
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);

FIFO#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) out_buffer <- mkPipelineFIFO();

method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    actionvalue
        out_buffer.deq();
        return out_buffer.first();
    endactionvalue
endmethod

method ActionValue#(UInt#(issuewidth_log_t)) consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(issuewidth_log_t) count);
    actionvalue
        for(Integer i = 0; i < valueOf(ISSUEWIDTH) && fromInteger(i) < count; i=i+1) begin
            dbg_print(Commit, $format(fshow(instructions[i])));
        end

        Vector#(ISSUEWIDTH, Maybe#(RegWrite)) temp_requests = replicate(tagged Invalid);

        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            if(fromInteger(i) < count &&& instructions[i].result matches tagged Result .r) begin
                temp_requests[i] = tagged Valid RegWrite {addr: instructions[i].destination, data: r};
            end
        end

        out_buffer.enq(temp_requests);

        return count;
    endactionvalue
endmethod

endmodule

endpackage