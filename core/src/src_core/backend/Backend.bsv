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
import ReorderBufferNew::*;
import Commit::*;
import RegFileArch::*;
import CSRFile::*;
import BuildVector::*;
`ifdef RVFI
    import RVFITracer::*;
`endif

// connections to external world
interface BackendIFC;
    method Action res_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);
    interface Get#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) train;
    interface Server#(Vector#(TMul#(2, ISSUEWIDTH), RegRead), Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) read_registers;
    interface Server#(CsrRead, Maybe#(Bit#(XLEN))) csr_read;
    method Action int_flags(Vector#(NUM_THREADS, Vector#(3, Bool)) int_mask);
    method Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc();
    (* always_enabled, always_ready *)
    method UInt#(TLog#(ROBDEPTH)) current_tail_idx;
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, Bit#(ISSUEWIDTH) mask);
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) rob_free;
    (* always_ready, always_enabled *)
    method Action hart_id(Bit#(TLog#(TMul#(NUM_CPU, NUM_THREADS))) in);
    interface Put#(CsrWrite) csr_write;

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif

    `ifdef DEXIE
        interface DExIETraceIfc dexie;
        (* always_ready, always_enabled *)
        method Action dexie_stall(Bool stall);
    `endif
endinterface

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

    // reg writing
    rule connect_commit_regs;
        let requests <- commit.get_write_requests();
        regfile_arch.write(requests);
    endrule

    // interrupt handling
    rule trap_vec;
        let v = csrf.trap_vectors();
        commit.trap_vectors(v);
    endrule
    rule trap_cause;
        let v <- commit.write_int_data();
        csrf.write_int_data(v);
    endrule

    // pass instructions from ROB to commit
    Wire#(UInt#(issuewidth_log_t)) deq_rob_wire <- mkDWire(0);
    rule connect_rob_commit;
        let insts <- rob.get();
        commit.consume_instructions(insts, rob.available());
    endrule

    `ifdef RVFI
        let trace <- mkRVFITracer();
        (* fire_when_enabled, no_implicit_conditions *)
        rule pass_rvfi;
            trace.rvfi_in(commit.rvfi_out());
        endrule
    `endif

    // methods to external world
    method Action res_bus(Vector#(NUM_FU, Maybe#(Result)) result_bus);
        rob.result_bus(result_bus);
    endmethod
    interface Get train = commit.train;
    
    interface read_registers = regfile_arch.read_registers();
    
    interface Server csr_read = csrf.read;

    method Action int_flags(Vector#(NUM_THREADS, Vector#(3, Bool)) int_mask);
        Vector#(NUM_THREADS, Bit#(3)) out;
        for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) begin
            Bit#(3) in_mask = {pack(int_mask[i][2]), pack(int_mask[i][1]), pack(int_mask[i][0])};
            out[i] = csrf.ext_interrupt_mask()[i] & in_mask();
        end
        commit.ext_interrupt_mask(out);
    endmethod

    method Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc() = commit.redirect_pc;
    method UInt#(TLog#(ROBDEPTH)) current_tail_idx = rob.current_tail_idx();
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, Bit#(ISSUEWIDTH) mask) = rob.reserve(data, mask);
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) rob_free = rob.free();
    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br = commit.correct_pred_br;
        method UInt#(XLEN) wrong_pred_br = commit.wrong_pred_br;
        method UInt#(XLEN) correct_pred_j = commit.correct_pred_j;
        method UInt#(XLEN) wrong_pred_j = commit.wrong_pred_j;
    `endif
    method Action hart_id(Bit#(TLog#(TMul#(NUM_CPU, NUM_THREADS))) in) = csrf.hart_id(in);

    interface Put csr_write = csrf.write();
    `ifdef DEXIE
        interface dexie = commit.dexie;
        interface dexie_stall = commit.dexie_stall;
    `endif
endmodule

endpackage