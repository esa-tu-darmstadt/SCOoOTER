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

//debug stuff
`ifdef EVA_BR
    Reg#(UInt#(XLEN)) correct_pred_br_r <- mkReg(0);
    Reg#(UInt#(XLEN)) wrong_pred_br_r <- mkReg(0);
    Reg#(UInt#(XLEN)) correct_pred_j_r <- mkReg(0);
    Reg#(UInt#(XLEN)) wrong_pred_j_r <- mkReg(0);
`endif

Reg#(UInt#(XLEN)) epoch <- mkReg(0);

Wire#(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA))) redirect_pc_w <- mkWire();

FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) memory_rq_out <- mkBypassFIFO();
FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), MIMO::LUInt#(ISSUEWIDTH))) branch_train <- mkBypassFIFO();

function Maybe#(MemWr) rob_entry_to_memory_write(RobEntry re) = re.epoch == epoch &&& re.mem_wr matches tagged Valid .v ? tagged Valid v : tagged Invalid; 

function Maybe#(TrainPrediction) rob_entry_to_train(RobEntry re);
    Maybe#(TrainPrediction) out;
    if (!re.branch || re.epoch != epoch) out = tagged Invalid;
    else out = tagged Valid TrainPrediction {pc: re.pc, target: re.next_pc, taken: re.pc+4 != re.next_pc, history: re.history, miss: re.pred_pc != re.next_pc, branch: re.br};
    return out;
endfunction

function Bool check_entry_for_mem_access(RobEntry entry) = (entry.mem_wr matches tagged Valid .v ? True : False);
method ActionValue#(UInt#(issuewidth_log_t)) consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(issuewidth_log_t) count);
    actionvalue
        //$display("commit ", fshow(instructions), " ", fshow(count));
        Vector#(ISSUEWIDTH, Maybe#(RegWrite)) temp_requests = replicate(tagged Invalid);

        Bool done = False;

        `ifdef EVA_BR
            UInt#(XLEN) correct_pred_br_local = correct_pred_br_r;
            UInt#(XLEN) wrong_pred_br_local = wrong_pred_br_r;
            UInt#(XLEN) correct_pred_j_local = correct_pred_j_r;
            UInt#(XLEN) wrong_pred_j_local = wrong_pred_j_r;
        `endif

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

                    if(instructions[i].branch == True 
                        && fromInteger(i) < count && 
                        instructions[i].next_pc == instructions[i].pred_pc) begin
                            `ifdef EVA_BR
                                if(instructions[i].br)
                                    correct_pred_br_local = correct_pred_br_local + 1;
                                else
                                    correct_pred_j_local = correct_pred_j_local + 1;
                            `endif
                        end
                end

                // check branch
                if(fromInteger(i) < count && instructions[i].next_pc != instructions[i].pred_pc && !done) begin
                    epoch <= epoch + 1;
                    // generate mispredict signal for IFU
                    redirect_pc_w <= tuple2(instructions[i].next_pc, instructions[i].ras);
                    done = True;
                    count_committed = fromInteger(i+1);
                    `ifdef EVA_BR
                        if(instructions[i].br)
                            wrong_pred_br_local = wrong_pred_br_local + 1;
                        else
                            wrong_pred_j_local = wrong_pred_j_local + 1;
                    `endif
                end

            end

            
        end

        out_buffer.enq(temp_requests);

        // memory write
        let writes = Vector::map(rob_entry_to_memory_write, instructions);
        memory_rq_out.enq(tuple2(writes, count_committed));

        // train predictor
        let trains = Vector::map(rob_entry_to_train, instructions);
        branch_train.enq(tuple2(trains, count_committed));

        // show prediction performance
        `ifdef EVA_BR
            correct_pred_br_r <= correct_pred_br_local;
            wrong_pred_br_r <= wrong_pred_br_local;
            correct_pred_j_r <= correct_pred_j_local;
            wrong_pred_j_r <= wrong_pred_j_local;
        `endif

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

method Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)) redirect_pc();
    return redirect_pc_w;
endmethod

method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    actionvalue
        out_buffer.deq();
        return out_buffer.first();
    endactionvalue
endmethod


interface Get train;
    method ActionValue#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), MIMO::LUInt#(ISSUEWIDTH))) get();
        actionvalue
            branch_train.deq();
            return branch_train.first();
        endactionvalue
    endmethod
endinterface

`ifdef EVA_BR
    method UInt#(XLEN) correct_pred_br = correct_pred_br_r;
    method UInt#(XLEN) wrong_pred_br = wrong_pred_br_r;
    method UInt#(XLEN) correct_pred_j = correct_pred_j_r;
    method UInt#(XLEN) wrong_pred_j = wrong_pred_j_r;
`endif

endmodule

endpackage