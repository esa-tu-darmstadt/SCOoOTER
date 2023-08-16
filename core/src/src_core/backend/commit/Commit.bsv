package Commit;

/*
  The COMMIT stage updates the architectural state.
  It dequeues instructions from the ROB and creates
  write requests for registers, CSRs and memory.

  If a branch misprediction occurs. the Commit stage
  redirects the FETCH stage and provides training data
  to the predictors.
*/

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
import FIFOF::*;
import TestFunctions::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkCommit(CommitIFC) provisos(
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t) //type to count inst from 0-ISSUEWIDTH
);

FIFO#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) out_buffer <- mkPipelineFIFO();

// those counters are used to track prediction performance
`ifdef EVA_BR
    Reg#(UInt#(XLEN)) correct_pred_br_r <- mkReg(0);
    Reg#(UInt#(XLEN)) wrong_pred_br_r <- mkReg(0);
    Reg#(UInt#(XLEN)) correct_pred_j_r <- mkReg(0);
    Reg#(UInt#(XLEN)) wrong_pred_j_r <- mkReg(0);
`endif

Vector#(NUM_THREADS, Reg#(UInt#(EPOCH_WIDTH))) epoch <- replicateM(mkReg(0));

Vector#(NUM_THREADS, Wire#(Bit#(XLEN))) trap_return_w <- replicateM(mkBypassWire());
Vector#(NUM_THREADS, Array#(Reg#(Bool))) int_in_process_r <- replicateM(mkCReg(2, False));

Vector#(NUM_THREADS, Array#(Reg#(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA))))) next_pc_r <- replicateM(mkCRegU(2));

Vector#(NUM_THREADS, FIFO#(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)))) redirect_pc_w <- replicateM(mkBypassFIFO());
Vector#(NUM_THREADS, RWire#(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)))) redirect_pc_w_exc <- replicateM(mkRWire());
Vector#(NUM_THREADS, RWire#(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)))) redirect_pc_w_out <- replicateM(mkRWire());

for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) // per thread
rule fwd_redir;
    redirect_pc_w_out[i].wset(redirect_pc_w[i].first());
    redirect_pc_w[i].deq();
endrule

Vector#(NUM_THREADS, Wire#(Bit#(XLEN))) tvec <- replicateM(mkBypassWire());
Vector#(NUM_THREADS, FIFO#(Tuple2#(Bit#(XLEN), Bit#(XLEN)))) mcause <- replicateM(mkPipelineFIFO());
Vector#(NUM_THREADS, RWire#(Tuple2#(Bit#(XLEN), Bit#(XLEN)))) mcause_exc <- replicateM(mkRWire());
Vector#(NUM_THREADS, RWire#(TrapDescription)) mcause_out <- replicateM(mkRWire());

for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) // per thread
rule fwd_mcause;
    let mcause_loc = mcause[i].first();
    mcause_out[i].wset(TrapDescription {cause: tpl_1(mcause_loc), pc: tpl_2(mcause_loc)});
    mcause[i].deq();
endrule

function Maybe#(a) read_rwire(RWire#(a) r) = r.wget();

Vector#(NUM_THREADS, Wire#(Bit#(3))) int_in <- replicateM(mkBypassWire());

FIFOF#(Vector#(ISSUEWIDTH, Maybe#(MemWr))) memory_rq_out <- mkPipelineFIFOF();
FIFO#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) branch_train <- mkPipelineFIFO();
FIFO#(Vector#(ISSUEWIDTH, Maybe#(CsrWrite))) csr_rq_out <- mkPipelineFIFO();


function Maybe#(MemWr) rob_entry_to_memory_write(RobEntry re) = re.epoch == epoch[re.thread_id] &&& re.write matches tagged Mem .v ? tagged Valid v : tagged Invalid; 
function Maybe#(CsrWrite) rob_entry_to_csr_write(RobEntry re) = re.epoch == epoch[re.thread_id] &&& re.write matches tagged Csr .v ? tagged Valid CsrWrite {addr: v.addr, data: v.data, thread_id: re.thread_id} : tagged Invalid; 
function Vector#(b, Maybe#(a)) mask_maybes(Vector#(b, Maybe#(a)) m, Bit#(b) f);
    for(Integer i = 0; i < valueOf(b); i=i+1) if (f[i] == 0) m[i] = tagged Invalid;
    return m;
endfunction

function Maybe#(TrainPrediction) rob_entry_to_train(RobEntry re);
    Maybe#(TrainPrediction) out;
    if (!re.branch || re.epoch != epoch[re.thread_id]) out = tagged Invalid;
    else out = tagged Valid TrainPrediction {pc: re.pc, target: re.next_pc, taken: re.pc+4 != re.next_pc, history: re.history, miss: re.pred_pc != re.next_pc, branch: re.br, thread_id: re.thread_id};
    return out;
endfunction

for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) // per thread
    rule redirect_on_no_interrupt (int_in[i] == 0 || int_in_process_r[i][1]);
        if(redirect_pc_w_exc[i].wget() matches tagged Valid .v) begin
            epoch[i] <= epoch[i] + 1;
            redirect_pc_w[i].enq(v);
        end
        if(mcause_exc[i].wget() matches tagged Valid .v) begin
            mcause[i].enq(v);
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

for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) // per thread
    rule redirect_on_interrupt (int_in[i] != 0 && !int_in_process_r[i][1]);
        epoch[i] <= epoch[i] + 1;
        int_in_process_r[i][1] <= True;
        redirect_pc_w[i].enq(tuple2(tvec[i], tpl_2(next_pc_r[i][1])));
        mcause[i].enq(tuple2({1'b1, fromInteger(cause_for_int(int_in[i]))}, tpl_1(next_pc_r[i][1])));
    endrule

`ifdef LOG_PIPELINE
    Reg#(UInt#(XLEN)) clk_ctr <- mkReg(0);
    Reg#(File) out_log <- mkRegU();
    rule count_clk; clk_ctr <= clk_ctr + 1; endrule
    rule open if (clk_ctr == 0);
        File out_log_l <- $fopen("scoooter.log", "a");
        out_log <= out_log_l;
    endrule
`endif

function Bool check_entry_for_mem_access(RobEntry entry) = (entry.write matches tagged Mem .v ? True : False);

method Action consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(issuewidth_log_t) count) if (memory_rq_out.notFull());
    action
        Vector#(ISSUEWIDTH, Maybe#(RegWrite)) temp_requests = replicate(tagged Invalid);

        Vector#(NUM_THREADS, Bool) done = replicate(False);

        `ifdef EVA_BR
            UInt#(XLEN) correct_pred_br_local = correct_pred_br_r;
            UInt#(XLEN) wrong_pred_br_local = wrong_pred_br_r;
            UInt#(XLEN) correct_pred_j_local = correct_pred_j_r;
            UInt#(XLEN) wrong_pred_j_local = wrong_pred_j_r;
        `endif

        // track which instructions were committed
        Bit#(ISSUEWIDTH) committed_mask = 0;

        // track next_pc
        Vector#(NUM_THREADS, Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA))) next_pc_local = Vector::readVReg(Vector::map(disassemble_creg(0), next_pc_r));

        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            let inst_thread_id = instructions[i].thread_id;

            if(instructions[i].epoch == epoch[inst_thread_id] && fromInteger(i) < count) begin

                `ifdef LOG_PIPELINE
                    if(done[inst_thread_id]) $fdisplay(out_log, "%d FLUSH %x %d", clk_ctr, instructions[i].pc, instructions[i].epoch);
                `endif

                if(!done[inst_thread_id]) begin
                    committed_mask[i] = 1; // set instruction to committed

                    // handle exceptions
                    if(instructions[i].result matches tagged Except .e) begin
                        instructions[i].next_pc = tvec[inst_thread_id];
                        instructions[i].pred_pc = ~tvec[inst_thread_id]; // force redirect
                        Bit#(31) except_code = extend(pack(e));
                        mcause_exc[inst_thread_id].wset(tuple2( {1'b0, except_code} , instructions[i].pc));
                    end

                    // handle returns
                    if(instructions[i].result matches tagged Result .r &&& 
                    instructions[i].ret) begin
                        instructions[i].next_pc = trap_return_w[inst_thread_id];
                        instructions[i].pred_pc = ~trap_return_w[inst_thread_id]; // force redirect
                        int_in_process_r[inst_thread_id][0] <= False;
                    end

                    // write registers
                    if(instructions[i].result matches tagged Result .r) begin
                        dbg_print(Commit, $format(fshow(instructions[i])));
                        temp_requests[i] = tagged Valid RegWrite {addr: instructions[i].destination, data: r, thread_id: inst_thread_id};

                        `ifdef LOG_PIPELINE
                            $fdisplay(out_log, "%d COMMIT %x %d", clk_ctr, instructions[i].pc, instructions[i].epoch);
                        `endif

                        if(instructions[i].branch == True && 
                            instructions[i].next_pc == instructions[i].pred_pc) begin
                                if(instructions[i].br) dbg_print(History, $format(" %b %b ", instructions[i].history, instructions[i].pc+4 != instructions[i].next_pc, fshow(instructions[i])));
                                `ifdef EVA_BR
                                    if(instructions[i].br)
                                        correct_pred_br_local = correct_pred_br_local + 1;
                                    else
                                        correct_pred_j_local = correct_pred_j_local + 1;
                                `endif
                            end
                    end

                    // check branch
                    if(instructions[i].next_pc != instructions[i].pred_pc) begin
                        // generate mispredict signal for IFU
                        redirect_pc_w_exc[inst_thread_id].wset(tuple2(instructions[i].next_pc, instructions[i].ras));
                        done[inst_thread_id] = True;
                        if(instructions[i].br) dbg_print(History, $format(" %b %b ", instructions[i].history, instructions[i].pc+4 != instructions[i].next_pc, fshow(instructions[i])));
                        `ifdef EVA_BR
                            if(instructions[i].br)
                                wrong_pred_br_local = wrong_pred_br_local + 1;
                            else
                                wrong_pred_j_local = wrong_pred_j_local + 1;
                        `endif
                    end

                    //update next_pc
                    next_pc_local[inst_thread_id] = tuple2(instructions[i].next_pc, instructions[i].ras);
                end
            end 
            `ifdef LOG_PIPELINE
                else if(fromInteger(i) < count) begin
                    $fdisplay(out_log, "%d FLUSH %x %d", clk_ctr, instructions[i].pc, instructions[i].epoch);
                end
            `endif

            
        end

        // update next PC
        for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
            next_pc_r[i][0] <= next_pc_local[i];

        // reg write
        out_buffer.enq(mask_maybes(temp_requests, committed_mask));

        // memory write
        let writes = Vector::map(rob_entry_to_memory_write, instructions);
        memory_rq_out.enq(mask_maybes(writes, committed_mask));

        // train predictor
        let trains = Vector::map(rob_entry_to_train, instructions);
        branch_train.enq(mask_maybes(trains, committed_mask));

        // csr writes
        let csrs = Vector::map(rob_entry_to_csr_write, instructions);
        csr_rq_out.enq(mask_maybes(csrs, committed_mask));

        // show prediction performance
        `ifdef EVA_BR
            correct_pred_br_r <= correct_pred_br_local;
            wrong_pred_br_r <= wrong_pred_br_local;
            correct_pred_j_r <= correct_pred_j_local;
            wrong_pred_j_r <= wrong_pred_j_local;
        `endif

    endaction
endmethod

interface GetS memory_writes;
    interface first = memory_rq_out.first();
    interface deq = memory_rq_out.deq();
endinterface

interface Get csr_writes = toGet(csr_rq_out);

method Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)))) redirect_pc();
    return Vector::map(read_rwire, redirect_pc_w_out);
endmethod

method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    actionvalue
        out_buffer.deq();
        return out_buffer.first();
    endactionvalue
endmethod


interface Get train;
    method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) get();
        actionvalue
            branch_train.deq();
            return branch_train.first();
        endactionvalue
    endmethod
endinterface

method Action trap_vectors(Vector#(NUM_THREADS, Tuple2#(Bit#(XLEN), Bit#(XLEN))) vecs);
    for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) begin
        tvec[i] <= tpl_1(vecs[i]);
        trap_return_w[i] <= tpl_2(vecs[i]);
    end
endmethod

method ActionValue#(Vector#(NUM_THREADS, Maybe#(TrapDescription))) write_int_data();
    return Vector::map(read_rwire, mcause_out);
endmethod

method Action ext_interrupt_mask(Vector#(NUM_THREADS, Bit#(3)) in);
    Vector::writeVReg(int_in, in);
endmethod

`ifdef EVA_BR
    method UInt#(XLEN) correct_pred_br = correct_pred_br_r;
    method UInt#(XLEN) wrong_pred_br = wrong_pred_br_r;
    method UInt#(XLEN) correct_pred_j = correct_pred_j_r;
    method UInt#(XLEN) wrong_pred_j = wrong_pred_j_r;
`endif

endmodule

endpackage