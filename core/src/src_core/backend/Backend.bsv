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
import StoreBuffer::*;
import BuildVector::*;

// connections to external world
interface BackendIFC;
    method Action res_bus(Tuple3#(Vector#(NUM_FU, Maybe#(Result)), Maybe#(MemWr), Maybe#(CsrWrite)) res_bus);
    interface Get#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) train;
    method Bool csr_busy();
    interface Client#(MemWr, void) write;
    interface Server#(Vector#(TMul#(2, ISSUEWIDTH), RADDR), Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) read_registers;
    interface Server#(UInt#(TLog#(ROBDEPTH)), Bool) check_pending_memory;
    interface Server#(Bit#(12), Maybe#(Bit#(XLEN))) csr_read;
    interface Server#(UInt#(XLEN), Maybe#(MaskedWord)) forward;
    method Action int_flags(Vector#(3, Bool) int_mask);
    method Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)) redirect_pc();
    (* always_enabled, always_ready *)
    method UInt#(TLog#(ROBDEPTH)) current_idx;
    (* always_enabled, always_ready *)
    method UInt#(TLog#(ROBDEPTH)) current_tail_idx;
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, UInt#(TLog#(TAdd#(1, ISSUEWIDTH))) num);
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) rob_free;
    method Bool store_queue_empty();
    (* always_ready, always_enabled *)
    method Action hart_id(Bit#(TLog#(NUM_CPU)) in);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
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
    let store_buf <- mkStoreBuffer();
    RobIFC rob <- mkReorderBuffer();
    CommitIFC commit <- mkCommit();
    RegFileIFC regfile_arch <- mkRegFile();

    // csr writing
    mkConnection(commit.csr_writes, csrf.writes);
    // mem writing
    rule pass_mem_to_sb;
        store_buf.memory_writes.put(commit.memory_writes.first());
    endrule
    rule deq_mem_wrs;
        if(store_buf.deq_memory_writes())
            commit.memory_writes.deq();
    endrule

    // reg writing
    rule connect_commit_regs;
        let requests <- commit.get_write_requests();
        regfile_arch.write(requests);
    endrule

    // interrupt handling
    rule trap_vec;
        let v = csrf.trap_vectors();
        uncurry(commit.trap_vectors)(v);
    endrule
    rule trap_cause;
        let v <- commit.write_int_data();
        uncurry(csrf.write_int_data)(v);
    endrule

    // pass instructions from ROB to commit
    Wire#(UInt#(issuewidth_log_t)) deq_rob_wire <- mkDWire(0);
    rule connect_rob_commit;
        let insts <- rob.get();
        commit.consume_instructions(insts, rob.available());
    endrule

    // methods to external world
    method Action res_bus(Tuple3#(Vector#(NUM_FU, Maybe#(Result)), Maybe#(MemWr), Maybe#(CsrWrite)) result_bus);
        rob.result_bus(result_bus);
    endmethod
    interface Get train = commit.train;
    method Bool csr_busy() = rob.csr_busy();
    interface Client write = store_buf.write;
    
    interface read_registers = regfile_arch.read_registers();
    
    interface Server check_pending_memory = rob.check_pending_memory;
    interface Server forward = store_buf.forward;
    interface Server csr_read = csrf.read;
    method Action int_flags(Vector#(3, Bool) int_mask);
        Bit#(3) in_mask = {pack(int_mask[2]), pack(int_mask[1]), pack(int_mask[0])};
        let in_mask_set = csrf.ext_interrupt_mask() & in_mask();
        commit.ext_interrupt_mask(in_mask_set);
    endmethod
    method Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)) redirect_pc() = commit.redirect_pc;
    method UInt#(TLog#(ROBDEPTH)) current_idx = rob.current_idx();
    method UInt#(TLog#(ROBDEPTH)) current_tail_idx = rob.current_tail_idx();
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, UInt#(TLog#(TAdd#(1, ISSUEWIDTH))) num) = rob.reserve(data, num);
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) rob_free = rob.free();
    method Bool store_queue_empty() = store_buf.empty();
    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br = commit.correct_pred_br;
        method UInt#(XLEN) wrong_pred_br = commit.wrong_pred_br;
        method UInt#(XLEN) correct_pred_j = commit.correct_pred_j;
        method UInt#(XLEN) wrong_pred_j = commit.wrong_pred_j;
    `endif
    method Action hart_id(Bit#(TLog#(NUM_CPU)) in) = csrf.hart_id(in);
endmodule

endpackage