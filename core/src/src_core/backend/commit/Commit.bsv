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

Wire#(Bit#(XLEN)) trap_return_w <- mkBypassWire();
Array#(Reg#(Bool)) int_in_process_r <- mkCReg(2, False);

Array#(Reg#(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)))) next_pc_r <- mkCRegU(2);

Wire#(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA))) redirect_pc_w <- mkWire();
RWire#(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA))) redirect_pc_w_exc <- mkRWire();

Wire#(Bit#(XLEN)) tvec <- mkWire();
FIFO#(Tuple2#(Bit#(XLEN), Bit#(XLEN))) mcause <- mkBypassFIFO();
RWire#(Tuple2#(Bit#(XLEN), Bit#(XLEN))) mcause_exc <- mkRWire();
Wire#(Bit#(3)) int_in <- mkBypassWire();

FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) memory_rq_out <- mkBypassFIFO();
FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), MIMO::LUInt#(ISSUEWIDTH))) branch_train <- mkBypassFIFO();
FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(CsrWrite)), MIMO::LUInt#(ISSUEWIDTH))) csr_rq_out <- mkBypassFIFO();


function Maybe#(MemWr) rob_entry_to_memory_write(RobEntry re) = re.epoch == epoch &&& re.write matches tagged Mem .v ? tagged Valid v : tagged Invalid; 
function Maybe#(CsrWrite) rob_entry_to_csr_write(RobEntry re) = re.epoch == epoch &&& re.write matches tagged Csr .v ? tagged Valid v : tagged Invalid; 


function Maybe#(TrainPrediction) rob_entry_to_train(RobEntry re);
    Maybe#(TrainPrediction) out;
    if (!re.branch || re.epoch != epoch) out = tagged Invalid;
    else out = tagged Valid TrainPrediction {pc: re.pc, target: re.next_pc, taken: re.pc+4 != re.next_pc, history: re.history, miss: re.pred_pc != re.next_pc, branch: re.br};
    return out;
endfunction

rule redirect_on_no_interrupt (int_in == 0 || int_in_process_r[1]);
    if(redirect_pc_w_exc.wget() matches tagged Valid .v) begin
        epoch <= epoch + 1;
        redirect_pc_w <= v;
    end
    if(mcause_exc.wget() matches tagged Valid .v) begin
        mcause.enq(v);
    end
    
endrule

function Integer cause_for_int(Bit#(3) flags);
    if(flags[0] == 1) begin
        return 11;
    end else if (flags[1] == 1) begin
        return 7;
    end else if (flags[2] == 1) begin
        return 3;
    end else return ?;

endfunction

rule redirect_on_interrupt (int_in != 0 && !int_in_process_r[1]);
    epoch <= epoch + 1;
    int_in_process_r[1] <= True;
    redirect_pc_w <= tuple2(tvec, tpl_2(next_pc_r[1]));
    mcause.enq(tuple2({1'b1, fromInteger(cause_for_int(int_in))}, tpl_1(next_pc_r[1])));
endrule

function Bool check_entry_for_mem_access(RobEntry entry) = (entry.write matches tagged Mem .v ? True : False);
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

                // handle exceptions
                if(fromInteger(i) < count &&& 
                   instructions[i].result matches tagged Except .e &&& 
                   !done) begin
                    instructions[i].next_pc = tvec;
                    instructions[i].pred_pc = ~tvec;
                    Bit#(31) except_code = extend(pack(instructions[i].result.Except));
                    mcause_exc.wset(tuple2( {1'b0, except_code} , instructions[i].pc));
                end

                // handle returns
                if(fromInteger(i) < count &&& 
                   instructions[i].result matches tagged Result .r &&& 
                   instructions[i].ret &&&
                   !done) begin
                    instructions[i].next_pc = trap_return_w;
                    instructions[i].pred_pc = ~trap_return_w;
                    int_in_process_r[0] <= False;
                end

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
                    // generate mispredict signal for IFU
                    redirect_pc_w_exc.wset(tuple2(instructions[i].next_pc, instructions[i].ras));
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

        if(count_committed != 0) next_pc_r[0] <= tuple2(instructions[count_committed-1].next_pc, instructions[count_committed-1].ras);

        out_buffer.enq(temp_requests);

        // memory write
        let writes = Vector::map(rob_entry_to_memory_write, instructions);
        memory_rq_out.enq(tuple2(writes, count_committed));

        // train predictor
        let trains = Vector::map(rob_entry_to_train, instructions);
        branch_train.enq(tuple2(trains, count_committed));

        // csr writes
        let csrs = Vector::map(rob_entry_to_csr_write, instructions);
        csr_rq_out.enq(tuple2(csrs, count_committed));

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

interface Get memory_writes = toGet(memory_rq_out);
interface Get csr_writes = toGet(csr_rq_out);

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

method Action trap_vectors(Bit#(XLEN) tv, Bit#(XLEN) ret);
    tvec <= tv;
    trap_return_w <= ret;
endmethod
method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(XLEN))) write_int_data();
    mcause.deq();
    return mcause.first();
endmethod

method Action ext_interrupt_mask(Bit#(3) in);
    int_in <= in;
endmethod

`ifdef EVA_BR
    method UInt#(XLEN) correct_pred_br = correct_pred_br_r;
    method UInt#(XLEN) wrong_pred_br = wrong_pred_br_r;
    method UInt#(XLEN) correct_pred_j = correct_pred_j_r;
    method UInt#(XLEN) wrong_pred_j = wrong_pred_j_r;
`endif

endmodule

endpackage