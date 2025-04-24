package Backend;

/*
  this is the backend part of the processor.
  It holds the architectural state,
  the COMMIT stage and the ROB.
*/

import Connectable :: *;
import Vector::*;
import ClientServer::*;
import Inst_Types::*;
import Types::*;
import GetPut::*;
import Interfaces::*;
import ReorderBuffer::*;
import Commit::*;
import RegFileArch::*;
import CSRFile::*;
import BuildVector::*;
`ifdef RVFI
    import RVFITracer::*;
`endif

// interface of the backend
interface BackendIFC;
    // result bus towards exec core
    method Action res_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);
    // branch prediction training interface towards frontend
    interface Get#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) train;
    // reg read interface towards issue stage
    interface Server#(Vector#(TMul#(2, ISSUEWIDTH), RegRead), Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) read_registers;
    // csr read iface towards CSR unit
    interface Server#(CsrRead, Maybe#(Bit#(XLEN))) csr_read;
    // incoming interrupt signals
    method Action int_flags(Vector#(NUM_THREADS, Vector#(3, Bool)) int_mask);
    // control flow redirection towards fetch stage
    method Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc();
    // next index to be dequeued - needed to guard speculative execution in CSR and Memory units
    (* always_enabled, always_ready *)
    method UInt#(TLog#(ROBDEPTH)) current_tail_idx;
    // reservation in ROB from issue stage
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, Bit#(ISSUEWIDTH) mask);
    // number of free rob slots for issue stage
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) rob_free;
    (* always_ready, always_enabled *)
    // base hart ID to be reported for the current processor
    // will be incremented for every hardware thread
    // will be forwarded to CSR file
    method Action hart_id(Bit#(TLog#(TMul#(NUM_CPU, NUM_THREADS))) in);
    // writes to the CSR file
    interface Put#(CsrWrite) csr_write;

    // branch prediction efficacy tracing
    // used in simulation
    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif

    // signals for the DExIE control flow integrity engine
    // used internally at ESA group for future develoment
    `ifdef DEXIE
        interface DExIETraceIfc dexie;
        (* always_ready, always_enabled *)
        method Action dexie_stall(Bool stall);
    `endif
endinterface


// backend module
// instantiates and connects the backend components
`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkBackend(BackendIFC) provisos (
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);

    // instantiate units
    let csrf <- mkCSRFile();
    RobIFC rob <- mkReorderBufferNew();
    CommitIFC commit <- mkCommit();
    RegFileIFC regfile_arch <- valueOf(REGFILE_LATCH_BASED) == 0 ? mkRegFile() : mkRegFileAriane();

    // register writing from commit to architectural regs
    rule connect_commit_regs;
        let requests <- commit.get_write_requests();
        regfile_arch.write(requests);
    endrule

    // interrupt handling
    // connect the interrupt-related CSRs to the commit stage for read/write
    rule trap_vec;
        let v = csrf.trap_vectors();
        commit.trap_vectors(v);
    endrule
    rule trap_cause;
        let v <- commit.write_int_data();
        csrf.write_int_data(v);
    endrule

    // connect Commit and ROB so that Commit can dequeue instructions from the ROB
    Wire#(UInt#(issuewidth_log_t)) deq_rob_wire <- mkDWire(0);
    rule connect_rob_commit;
        let insts <- rob.get();
        commit.consume_instructions(insts, rob.available());
    endrule

    // generate the RVFI trace and store it t a file for Core-V-Verif
    `ifdef RVFI
        let trace <- mkRVFITracer();
        (* fire_when_enabled, no_implicit_conditions *)
        rule pass_rvfi;
            trace.rvfi_in(commit.rvfi_out());
        endrule
    `endif

    // external interface connection

    // connect the result bus from the execution core to the ROB
    method Action res_bus(Vector#(NUM_FU, Maybe#(Result)) result_bus);
        rob.result_bus(result_bus);
    endmethod

    // mask enabled interrupts and notify interrupts to commit
    method Action int_flags(Vector#(NUM_THREADS, Vector#(3, Bool)) int_mask);
        Vector#(NUM_THREADS, Bit#(3)) out;
        for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) begin
            Bit#(3) in_mask = {pack(int_mask[i][2]), pack(int_mask[i][1]), pack(int_mask[i][0])};
            out[i] = csrf.ext_interrupt_mask()[i] & in_mask();
        end
        commit.ext_interrupt_mask(out);
    endmethod

    // register writes and reads
    interface Put csr_write = csrf.write();
    interface read_registers = regfile_arch.read_registers();
    interface Server csr_read = csrf.read;
    method Action hart_id(Bit#(TLog#(TMul#(NUM_CPU, NUM_THREADS))) in) = csrf.hart_id(in);

    // ROB reservations and signals
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, Bit#(ISSUEWIDTH) mask) = rob.reserve(data, mask);
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) rob_free = rob.free();
    method UInt#(TLog#(ROBDEPTH)) current_tail_idx = rob.current_tail_idx();

    // training and redirection for branch prediction
    interface Get train = commit.train;
    method Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc() = commit.redirect_pc;

    // branch prediction efficacy tracking
    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br = commit.correct_pred_br;
        method UInt#(XLEN) wrong_pred_br = commit.wrong_pred_br;
        method UInt#(XLEN) correct_pred_j = commit.correct_pred_j;
        method UInt#(XLEN) wrong_pred_j = commit.wrong_pred_j;
    `endif

    // signals for the optional DExIE control flow integrity engine
    `ifdef DEXIE
        interface dexie = commit.dexie;
        method Action dexie_stall(Bool stall);
            commit.dexie_stall(stall);
            rob.dexie_stall(stall);
        endmethod
    `endif
endmodule

endpackage