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

// open files for pipeline logging
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

// buffer register writes
FIFO#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) out_buffer <- mkPipelineFIFO();

// those counters are used to track prediction performance
`ifdef EVA_BR
    Reg#(UInt#(XLEN)) correct_pred_br_r <- mkReg(0);
    Reg#(UInt#(XLEN)) wrong_pred_br_r <- mkReg(0);
    Reg#(UInt#(XLEN)) correct_pred_j_r <- mkReg(0);
    Reg#(UInt#(XLEN)) wrong_pred_j_r <- mkReg(0);
`endif

// epoch register for misprediction tracking
Vector#(NUM_THREADS, Reg#(UInt#(EPOCH_WIDTH))) epoch <- replicateM(mkReg(0));

// feedback from CSRFile: 
Vector#(NUM_THREADS, Wire#(Bit#(XLEN))) trap_return_w <- replicateM(mkBypassWire());

// flag to disable interrupts while one is handled
Vector#(NUM_THREADS, Array#(Reg#(Bool))) int_in_process_r <- replicateM(mkCReg(2, False));

// save next PC from previous cycle for exceptions
Vector#(NUM_THREADS, Array#(Reg#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA))))) next_pc_r <- replicateM(mkCRegU(2));

// PC redirection signals for internal exceptions and external interrupts
Vector#(NUM_THREADS, RWire#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc_w_exc <- replicateM(mkRWire());
Vector#(NUM_THREADS, RWire#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc_w_out <- replicateM(mkRWire());

// incoming trap vector from CSRFile
Vector#(NUM_THREADS, Wire#(Bit#(XLEN))) tvec <- replicateM(mkBypassWire());
// buffering for MCAUSE CSR writes
Vector#(NUM_THREADS, RWire#(Tuple3#(Bit#(XLEN), Bit#(PCLEN), Bit#(XLEN)))) mcause_exc <- replicateM(mkRWire());
Vector#(NUM_THREADS, RWire#(TrapDescription)) mcause_out <- replicateM(mkRWire());

// incoming interrupt signals (SW, EXT, TIMER)
Vector#(NUM_THREADS, Wire#(Bit#(3))) int_in <- replicateM(mkBypassWire());

// outgoing branch prediction training signals
FIFO#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) branch_train <- mkPipelineFIFO();

// helper function to convert ROB entry to branch predictor training info
function Maybe#(TrainPrediction) rob_entry_to_train(RobEntry re);
    Maybe#(TrainPrediction) out;
    if (!re.branch || re.epoch != epoch[re.thread_id]) out = tagged Invalid;
    else out = tagged Valid TrainPrediction {pc: re.pc, target: re.next_pc, taken: re.pc+4 != re.next_pc, history: re.history, miss: re.pred_pc != re.next_pc, branch: re.br, thread_id: re.thread_id};
    return out;
endfunction

PulseWire dx_allow_int <- mkPulseWire();
// per HART: redirect if an internal exception occurs
for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) // per thread
    rule redirect_on_no_interrupt
    `ifdef DEXIE
        (!dx_allow_int);
    `else
        (int_in[i] == 0 || int_in_process_r[i][1]); // no external interrupt or currently handled int
    `endif
        if(redirect_pc_w_exc[i].wget() matches tagged Valid .v) begin // if an interrupt redirtection address is available
            epoch[i] <= epoch[i] + 1; // increment epoch
            redirect_pc_w_out[i].wset(v); // send redirection to frontend
        end
        if(mcause_exc[i].wget() matches tagged Valid .v) begin // set mcause if requested
            mcause_out[i].wset(TrapDescription {cause: tpl_1(v), pc: tpl_2(v), val: tpl_3(v)}); // send to CSRFile
        end   
    endrule

// helper function to get interrupt ID from the three incoming interrupt signals
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
    Vector#(ISSUEWIDTH, Wire#(RVFIBus)) rvfi <- replicateM(mkDWire(unpack(0))); // buffer for bus signals
    Vector#(NUM_THREADS, Ehr#(ISSUEWIDTH, UInt#(XLEN))) count_insts <- replicateM(mkEhr(0)); // counter for committed instructions
    Ehr#(TAdd#(ISSUEWIDTH, 1), Bool) first_trap <- mkEhr(False); // boolean to mark first instruction of trap handler
`endif

for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) // per thread
    rule redirect_on_interrupt 
    `ifdef DEXIE
        (dx_allow_int); // no interrupt in progress and incoming interrupt signal set
    `else
        (int_in[i] != 0 && !int_in_process_r[i][1]);
    `endif
        dbg_print(Commit, $format("Interrupt!"));
        epoch[i] <= epoch[i] + 1; // increase epoch
        int_in_process_r[i][1] <= True; // interrupt handler in progress
        redirect_pc_w_out[i].wset(tuple2(truncateLSB(tvec[i]), tpl_2(next_pc_r[i][1]))); // redirect frontend
        mcause_out[i].wset(TrapDescription {cause: {1'b1, fromInteger(cause_for_int(int_in[i]))}, pc: tpl_1(next_pc_r[i][1]), val: 0}); // write to CSRFile
        `ifdef RVFI
            first_trap[valueOf(ISSUEWIDTH)] <= False; // first trap handling instruction shall be marked
        `endif
    endrule

// helper function to apply a bitmask to a vector of maybe values
function Vector#(b, Maybe#(a)) mask_maybes(Vector#(b, Maybe#(a)) m, Bit#(b) f);
    for(Integer i = 0; i < valueOf(b); i=i+1) if (f[i] == 0) m[i] = tagged Invalid;
    return m;
endfunction

// trace signals for DExIE
`ifdef DEXIE
    Vector#(ISSUEWIDTH, RWire#(DexieCF)) dexie_control_flow <- replicateM(mkRWire());
    Vector#(ISSUEWIDTH, RWire#(DexieReg)) dexie_reg_write <- replicateM(mkRWire());
    Wire#(Bool) dexie_stall_w <- mkBypassWire();
`endif


// main commit method - gets instructions and creates all commit outputs
method Action consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(issuewidth_log_t) count) 
    `ifdef DEXIE
        if (!dexie_stall_w) // stalled by DExIE if necessary
    `endif
;
    // local variable for register writes
    Vector#(ISSUEWIDTH, Maybe#(RegWrite)) temp_requests = replicate(tagged Invalid);
    // local variable to signify commit done per thread
    Vector#(NUM_THREADS, Bool) done = replicate(False);

    // branch prediction efficacy evaluation
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

    // loop over all incoming instructions
    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
        let inst_thread_id = instructions[i].thread_id; // get thread id of instruction
    
        if(instructions[i].epoch == epoch[inst_thread_id] && fromInteger(i) < count) begin // check that instruction is valid and has correct epoch

            // write flushed instructions to the pipeline log
            `ifdef LOG_PIPELINE
                if(done[inst_thread_id]) begin
                    $fdisplay(out_log, "%d FLUSH %x %d", clk_ctr, {instructions[i].pc, 2'b00}, instructions[i].epoch);
                    $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, instructions[i].log_id, 0, "X");
                    $fdisplay(out_log_ko, "%d R %d %d %d", clk_ctr, instructions[i].log_id, instructions[i].log_id, 1);
                end
            `endif

            // if the done flag for this HART is not set, the instruction is valid and should be handled
            if(!done[inst_thread_id]) begin
                // handle exceptions
                if(instructions[i].result matches tagged Except .e) begin
                    instructions[i].next_pc = truncateLSB(tvec[inst_thread_id]);
                    instructions[i].pred_pc = ~truncateLSB(tvec[inst_thread_id]); // force redirect, pred and next pc are guaranteed to be different
                    Bit#(31) except_code = extend(pack(e)); // generate exception code for mcause
                    // write MCAUSE register
                    `ifdef RVFI
                        // RVFI needs memory address passed
                        mcause_exc[inst_thread_id].wset(tuple3( {1'b0, except_code} , instructions[i].pc, pack(instructions[i].mem_addr)));
                    `else
                        mcause_exc[inst_thread_id].wset(tuple3( {1'b0, except_code} , instructions[i].pc, 32'hdeadbeef));
                    `endif
                    // log exception if commit logging is on
                    dbg_print(Commit, $format("EXCEPT: ", fshow(instructions[i])));

                    // special handling for ECALL instruction - only required for logging
                    if (e == ECALL_M) begin
                        int_in_process_r[inst_thread_id][0] <= True;
                        dbg_print(Commit, $format("Ecall!"));
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

                end else // not an exception and valid instruction
                    committed_mask[i] = 1; // set instruction to committed
            
                // handle returns
                if(instructions[i].result matches tagged Result .r &&& 
                    instructions[i].ret) begin
                    instructions[i].next_pc = truncateLSB(trap_return_w[inst_thread_id]+1);
                    instructions[i].pred_pc = ~truncateLSB(trap_return_w[inst_thread_id]+1); // force redirect, pred and next pc are guaranteed to be different
                    int_in_process_r[inst_thread_id][0] <= False; // end interrupt handling
                    dbg_print(Commit, $format("Return!"));
                end

                // write registers
                if(instructions[i].result matches tagged Result .r) begin // is a reg write
                    dbg_print(Commit, $format(fshow({instructions[i].pc, 2'b00}), " ", fshow(instructions[i]))); // print commit if logging enabled
                    temp_requests[i] = tagged Valid RegWrite {addr: instructions[i].destination, data: r, thread_id: inst_thread_id}; // create write

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

                    // write pipeline log
                    `ifdef LOG_PIPELINE
                        $fdisplay(out_log, "%d COMMIT %x %d", clk_ctr, {instructions[i].pc, 2'b00}, instructions[i].epoch);
                        $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, instructions[i].log_id, 0, "X");
                        $fdisplay(out_log_ko, "%d R %d %d %d", clk_ctr, instructions[i].log_id, instructions[i].log_id, 0);
                    `endif

                    // handle control flow logging for correct prediction
                    if(instructions[i].branch == True &&  // instruction is branch type
                        instructions[i].next_pc == instructions[i].pred_pc) begin // prediction was wrong
                            // log branch prediction history
                            if(instructions[i].br) dbg_print(History, $format(" %b %b ", instructions[i].history, {instructions[i].pc, 2'b00}+4 != {instructions[i].next_pc, 2'b00}, fshow(instructions[i])));
                            // evaluate quality of branch prediction
                            `ifdef EVA_BR
                                if(instructions[i].br)
                                    correct_pred_br_local = correct_pred_br_local + 1;
                                else
                                    correct_pred_j_local = correct_pred_j_local + 1;
                            `endif
                        end
                    end

                    // handle control flow redirect on wrong predictions
                    if(instructions[i].next_pc != instructions[i].pred_pc) begin
                        // generate mispredict signal for IFU
                        redirect_pc_w_exc[inst_thread_id].wset(tuple2(instructions[i].next_pc, instructions[i].ras));
                        done[inst_thread_id] = True; // do not consume further instructions from this thread since they are false-path
                        // log branch prediction history
                        if(instructions[i].br) dbg_print(History, $format(" %b %b ", instructions[i].history, instructions[i].pc+1 != instructions[i].next_pc, fshow(instructions[i])));
                        // evaluate quality of branch prediction
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
            // write DExIE trace
            `ifdef DEXIE
                Bool interrupt_allowed_constraint1 = instructions[i].dexie_type matches tagged Memory &&& int_in[i] != 0 &&& (!int_in_process_r[i][0]) ? True : False;
                Bool interrupt_allowed_constraint2 = instructions[i].dexie_type matches tagged Register &&& int_in[i] != 0 &&& (!int_in_process_r[i][0]) ? True : False;
                Bool interrupt_allowed_constraint = interrupt_allowed_constraint1 || interrupt_allowed_constraint2;

                if (interrupt_allowed_constraint) dx_allow_int.send();
                dexie_control_flow[i].wset(DexieCF {pc: instructions[i].pc, instruction: instructions[i].dexie_iword, next_pc: interrupt_allowed_constraint ? truncate(tvec[i] >> 2) : instructions[i].next_pc});
                if (instructions[i].dexie_type matches tagged Register) dexie_reg_write[i].wset(DexieReg {pc: instructions[i].pc, destination: instructions[i].destination, data: instructions[i].result.Result});
            `endif
            end 
            // log flushed instructions for pipeline log
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

        // output register writes
        out_buffer.enq(mask_maybes(temp_requests, committed_mask));

        // generate predictor training information
        let trains = Vector::map(rob_entry_to_train, instructions);
        branch_train.enq(mask_maybes(trains, committed_mask));

        // show prediction performance
        `ifdef EVA_BR
            correct_pred_br_r <= correct_pred_br_local;
            wrong_pred_br_r <= wrong_pred_br_local;
            correct_pred_j_r <= correct_pred_j_local;
            wrong_pred_j_r <= wrong_pred_j_local;
        `endif

endmethod

// output redirect signal to frontend
method Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc();
    return Vector::map(get_r_wire, redirect_pc_w_out);
endmethod

// return training data for branch prediction
interface Get train;
    method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) get();
        actionvalue
            branch_train.deq();
            return branch_train.first();
        endactionvalue
    endmethod
endinterface

// get trap-related data from CSRFile
method Action trap_vectors(Vector#(NUM_THREADS, Tuple2#(Bit#(XLEN), Bit#(XLEN))) vecs);
    for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) begin
        tvec[i] <= tpl_1(vecs[i]);
        trap_return_w[i] <= tpl_2(vecs[i]);
    end
endmethod

// write interrupt data to CSRFile
method ActionValue#(Vector#(NUM_THREADS, Maybe#(TrapDescription))) write_int_data();
    return Vector::map(get_r_wire, mcause_out);
endmethod

// input for interrupt signals from outside world
method Action ext_interrupt_mask(Vector#(NUM_THREADS, Bit#(3)) in);
    Vector::writeVReg(int_in, in);
endmethod

// output for register writes to regfile
method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    actionvalue
        out_buffer.deq();
        return out_buffer.first();
    endactionvalue
endmethod

// output branch prediction efficacy data
`ifdef EVA_BR
    method UInt#(XLEN) correct_pred_br = correct_pred_br_r;
    method UInt#(XLEN) wrong_pred_br = wrong_pred_br_r;
    method UInt#(XLEN) correct_pred_j = correct_pred_j_r;
    method UInt#(XLEN) wrong_pred_j = wrong_pred_j_r;
`endif

//output RVFI
`ifdef RVFI
    interface rvfi_out = Vector::readVReg(rvfi);
`endif

// output DExIE trace info and get dexie stall signals
`ifdef DEXIE
    interface DExIETraceIfc dexie;
        method Vector#(ISSUEWIDTH, Maybe#(DexieCF)) cf = Vector::map(get_r_wire, dexie_control_flow);
        method Vector#(ISSUEWIDTH, Maybe#(DexieReg)) regw = Vector::map(get_r_wire, dexie_reg_write);
    endinterface
    method Action dexie_stall(Bool stall) = dexie_stall_w._write(stall);
`endif

endmodule

endpackage
