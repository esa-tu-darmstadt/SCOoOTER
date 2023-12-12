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
import Ehr::*;

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

Vector#(NUM_THREADS, Array#(Reg#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA))))) next_pc_r <- replicateM(mkCRegU(2));

Vector#(NUM_THREADS, FIFO#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc_w <- replicateM(mkBypassFIFO());
Vector#(NUM_THREADS, RWire#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc_w_exc <- replicateM(mkRWire());
Vector#(NUM_THREADS, RWire#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc_w_out <- replicateM(mkRWire());

for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) // per thread
rule fwd_redir;
    redirect_pc_w_out[i].wset(redirect_pc_w[i].first());
    redirect_pc_w[i].deq();
endrule

Vector#(NUM_THREADS, Wire#(Bit#(XLEN))) tvec <- replicateM(mkBypassWire());
Vector#(NUM_THREADS, FIFO#(Tuple3#(Bit#(XLEN), Bit#(PCLEN), Bit#(XLEN)))) mcause <- replicateM(mkPipelineFIFO());
Vector#(NUM_THREADS, RWire#(Tuple3#(Bit#(XLEN), Bit#(PCLEN), Bit#(XLEN)))) mcause_exc <- replicateM(mkRWire());
Vector#(NUM_THREADS, RWire#(TrapDescription)) mcause_out <- replicateM(mkRWire());

for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) // per thread
rule fwd_mcause;
    let mcause_loc = mcause[i].first();
    mcause_out[i].wset(TrapDescription {cause: tpl_1(mcause_loc), pc: tpl_2(mcause_loc), val: tpl_3(mcause_loc)});
    mcause[i].deq();
endrule

function Maybe#(a) read_rwire(RWire#(a) r) = r.wget();

Vector#(NUM_THREADS, Wire#(Bit#(3))) int_in <- replicateM(mkBypassWire());

FIFO#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) branch_train <- mkPipelineFIFO();

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

//RVFI:
`ifdef RVFI
    Vector#(ISSUEWIDTH, Wire#(RVFIBus)) rvfi <- replicateM(mkDWire(unpack(0)));
    Vector#(NUM_THREADS, Ehr#(ISSUEWIDTH, UInt#(XLEN))) count_insts <- replicateM(mkEhr(0));
    Ehr#(TAdd#(ISSUEWIDTH, 1), Bool) first_trap <- mkEhr(False);
`endif

for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) // per thread
    rule redirect_on_interrupt (int_in[i] != 0 && !int_in_process_r[i][1]);
        epoch[i] <= epoch[i] + 1;
        int_in_process_r[i][1] <= True;
        redirect_pc_w[i].enq(tuple2(truncateLSB(tvec[i]), tpl_2(next_pc_r[i][1])));
        mcause[i].enq(tuple3({1'b1, fromInteger(cause_for_int(int_in[i]))}, tpl_1(next_pc_r[i][1]), 0));
        `ifdef RVFI
            first_trap[valueOf(ISSUEWIDTH)] <= False;
        `endif
    endrule

`ifdef LOG_PIPELINE
    Reg#(UInt#(XLEN)) clk_ctr <- mkReg(0);
    Reg#(File) out_log <- mkRegU();
    Reg#(File) out_log_ko <- mkRegU();
    rule count_clk; clk_ctr <= clk_ctr + 1; endrule
    rule open if (clk_ctr == 0);
        File out_log_l <- $fopen("scoooter.log", "a");
        out_log <= out_log_l;
        File out_log_kol <- $fopen("konata.log", "a");
        out_log_ko <= out_log_kol;
    endrule
`endif

function Vector#(b, Maybe#(a)) mask_maybes(Vector#(b, Maybe#(a)) m, Bit#(b) f);
    for(Integer i = 0; i < valueOf(b); i=i+1) if (f[i] == 0) m[i] = tagged Invalid;
    return m;
endfunction

method Action consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(issuewidth_log_t) count);
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
        Vector#(NUM_THREADS, Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA))) next_pc_local = Vector::readVReg(Vector::map(disassemble_creg(0), next_pc_r));

        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            let inst_thread_id = instructions[i].thread_id;

            if(instructions[i].epoch == epoch[inst_thread_id] && fromInteger(i) < count) begin

                `ifdef LOG_PIPELINE
                    if(done[inst_thread_id]) begin
                        $fdisplay(out_log, "%d FLUSH %x %d", clk_ctr, {instructions[i].pc, 2'b00}, instructions[i].epoch);
                        $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, instructions[i].log_id, 0, "X");
                        $fdisplay(out_log_ko, "%d R %d %d %d", clk_ctr, instructions[i].log_id, instructions[i].log_id, 1);
                    end
                `endif

                if(!done[inst_thread_id]) begin
                    // handle exceptions
                    if(instructions[i].result matches tagged Except .e) begin
                        instructions[i].next_pc = truncateLSB(tvec[inst_thread_id]);
                        instructions[i].pred_pc = ~truncateLSB(tvec[inst_thread_id]); // force redirect
                        Bit#(31) except_code = extend(pack(e));
                        `ifdef RVFI
                            mcause_exc[inst_thread_id].wset(tuple3( {1'b0, except_code} , instructions[i].pc, pack(instructions[i].mem_addr)));
                        `else
                            mcause_exc[inst_thread_id].wset(tuple3( {1'b0, except_code} , instructions[i].pc, 32'hdeadbeef));
                        `endif
                        dbg_print(Commit, $format("EXCEPT: ", fshow(instructions[i])));

                        if (e == ECALL_M) begin
                            `ifdef RVFI
                                // generate RVFI frame
                                RVFIBus rvfi_i = unpack(0);
                                rvfi_i.valid = True;
                                rvfi_i.order = count_insts[instructions[i].thread_id][i];
                                rvfi_i.intr = first_trap[i];
                                rvfi_i.trap = (instructions[i].result matches tagged Except .e ? True : False);
                                rvfi_i.dbg = False;
                                rvfi_i.mode = 3;
                                rvfi_i.pc_rdata = {instructions[i].pc, 2'b00};
                                rvfi_i.pc_wdata = {instructions[i].next_pc, 2'b00};
                                rvfi_i.rd1_addr = 0;
                                rvfi_i.insn = instructions[i].iword;
                                rvfi_i.thread_id = instructions[i].thread_id;

                                rvfi[i] <= rvfi_i;

                                first_trap[i] <= False;
                                count_insts[instructions[i].thread_id][i] <= count_insts[instructions[i].thread_id][i]+1;
                            `endif
                        end

                    end else
                        committed_mask[i] = 1; // set instruction to committed

                    // handle returns
                    if(instructions[i].result matches tagged Result .r &&& 
                    instructions[i].ret) begin
                        instructions[i].next_pc = truncateLSB(trap_return_w[inst_thread_id]);
                        instructions[i].pred_pc = ~truncateLSB(trap_return_w[inst_thread_id]); // force redirect
                        int_in_process_r[inst_thread_id][0] <= False;
                    end

                    // write registers
                    if(instructions[i].result matches tagged Result .r) begin
                        dbg_print(Commit, $format(fshow({instructions[i].pc, 2'b00}), " ", fshow(instructions[i])));
                        temp_requests[i] = tagged Valid RegWrite {addr: instructions[i].destination, data: r, thread_id: inst_thread_id};

                        `ifdef RVFI
                            // generate RVFI frame
                            RVFIBus rvfi_i = unpack(0);
                            rvfi_i.valid = True;
                            rvfi_i.order = count_insts[instructions[i].thread_id][i];
                            rvfi_i.intr = first_trap[i];
                            rvfi_i.trap = (instructions[i].result matches tagged Except .e ? True : False);
                            rvfi_i.dbg = False;
                            rvfi_i.mode = 3;
                            rvfi_i.pc_rdata = {instructions[i].pc, 2'b00};
                            rvfi_i.pc_wdata = {instructions[i].next_pc, 2'b00};
                            rvfi_i.rd1_addr = instructions[i].destination;
                            if (rvfi_i.rd1_addr != 0 &&& instructions[i].result matches tagged Result .r) rvfi_i.rd1_wdata = r;
                            rvfi_i.insn = instructions[i].iword;
                            rvfi_i.thread_id = instructions[i].thread_id;

                            rvfi[i] <= rvfi_i;

                            first_trap[i] <= False;
                            count_insts[instructions[i].thread_id][i] <= count_insts[instructions[i].thread_id][i]+1;
                        `endif

                        `ifdef LOG_PIPELINE
                            $fdisplay(out_log, "%d COMMIT %x %d", clk_ctr, {instructions[i].pc, 2'b00}, instructions[i].epoch);
                            $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, instructions[i].log_id, 0, "X");
                            $fdisplay(out_log_ko, "%d R %d %d %d", clk_ctr, instructions[i].log_id, instructions[i].log_id, 0);
                        `endif

                        if(instructions[i].branch == True && 
                            instructions[i].next_pc == instructions[i].pred_pc) begin
                                if(instructions[i].br) dbg_print(History, $format(" %b %b ", instructions[i].history, {instructions[i].pc, 2'b00}+4 != {instructions[i].next_pc, 2'b00}, fshow(instructions[i])));
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
                        if(instructions[i].br) dbg_print(History, $format(" %b %b ", instructions[i].history, instructions[i].pc+1 != instructions[i].next_pc, fshow(instructions[i])));
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
                    $fdisplay(out_log, "%d FLUSH %x %d", clk_ctr, {instructions[i].pc, 2'b00}, instructions[i].epoch);
                    $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, instructions[i].log_id, 0, "X");
                    $fdisplay(out_log_ko, "%d R %d %d %d", clk_ctr, instructions[i].log_id, instructions[i].log_id, 1); 
                end
            `endif

            
        end

        // update next PC
        for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
            next_pc_r[i][0] <= next_pc_local[i];

        // reg write
        out_buffer.enq(mask_maybes(temp_requests, committed_mask));

        // train predictor
        let trains = Vector::map(rob_entry_to_train, instructions);
        branch_train.enq(mask_maybes(trains, committed_mask));

        // show prediction performance
        `ifdef EVA_BR
            correct_pred_br_r <= correct_pred_br_local;
            wrong_pred_br_r <= wrong_pred_br_local;
            correct_pred_j_r <= correct_pred_j_local;
            wrong_pred_j_r <= wrong_pred_j_local;
        `endif

    endaction
endmethod

method Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc();
    return Vector::map(read_rwire, redirect_pc_w_out);
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

method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    actionvalue
        out_buffer.deq();
        return out_buffer.first();
    endactionvalue
endmethod


`ifdef EVA_BR
    method UInt#(XLEN) correct_pred_br = correct_pred_br_r;
    method UInt#(XLEN) wrong_pred_br = wrong_pred_br_r;
    method UInt#(XLEN) correct_pred_j = correct_pred_j_r;
    method UInt#(XLEN) wrong_pred_j = wrong_pred_j_r;
`endif

//RVFI
`ifdef RVFI
    interface rvfi_out = Vector::readVReg(rvfi);
`endif

endmodule

endpackage
