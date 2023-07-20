package SCOOOTER_riscv;

import BlueAXI::*;
import Interfaces::*;
import Fetch::*;
import Types::*;
import ReservationStation::*;
import BuildVector::*;
import Vector::*;
import List::*;
import Inst_Types::*;
import BuildList::*;
import Arith::*;
import ReorderBuffer :: *;
import Debug::*;
import Commit::*;
import RegFileArch::*;
import RegFileEvo::*;
import Decode::*;
import Issue::*;
import Branch::*;
import Mem::*;
import GetPut::*;
import Connectable :: *;
import MulDiv::*;
import StoreBuffer::*;
import BTB::*;
import Smiths::*;
import AlwaysUntaken::*;
import Gshare::*;
import Gskewed::*;
import RAS::*;
import CSR::*;
import CSRFile::*;
import Frontend::*;
import ExecCore::*;
import Backend::*;
import ShiftBuffer::*;

(* synthesize *)
module mkSCOOOTER_riscv(Top) provisos(
        Mul#(XLEN, IFUINST, ifuwidth),
        Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
        Log#(issuewidth_pad_t, issuewidth_log_t),
        Log#(NUM_CPU, idx_cpu_t)
    );

    let fe <- mkFrontend();
    let ec <- mkExecCore();
    let be <- mkBackend();

    
    rule rob_csr;
        let b = be.csr_busy();
        ec.csr_busy(b);
    endrule

    mkConnection(be.train, fe.train);

    rule propagate_memory_guards;
        ec.store_queue_empty(be.store_queue_empty());
    endrule

    mkConnection(be.read_registers, ec.read_committed);

    rule propagate_result_bus;
        be.res_bus(ec.res_bus());
    endrule

    
    mkConnection(be.check_pending_memory, ec.check_rob);
    mkConnection(be.forward, ec.check_store_buffer);

    mkConnection(ec.csr_read, be.csr_read);

    Wire#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) evo_wire <- mkWire();

    mkConnection(ec.decoded_inst, fe.decoded_inst);

    rule flush_prints;
        $fflush();
    endrule

    rule commit_to_fetch;
        ec.flush();
        fe.redirect(be.redirect_pc());
    endrule

    rule connect_rob_issue;
        ec.rob_free(be.rob_free());
        ec.rob_current_idx(be.current_idx());
    endrule

    rule connect_rob_issue2;
        let req = ec.get_reservation();
        uncurry(be.reserve)(req);
    endrule

    Vector#(3, Wire#(Bool)) int_mask <- replicateM(mkBypassWire());
    rule push_int;
        be.int_flags(Vector::readVReg(int_mask));
    endrule

    // interrupts
    method Action sw_int(Bool b) = int_mask[2]._write(b);
    method Action timer_int(Bool b) = int_mask[1]._write(b);
    method Action ext_int(Bool b) = int_mask[0]._write(b);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br = be.correct_pred_br;
        method UInt#(XLEN) wrong_pred_br = be.wrong_pred_br;
        method UInt#(XLEN) correct_pred_j = be.correct_pred_j;
        method UInt#(XLEN) wrong_pred_j = be.wrong_pred_j;
    `endif

    interface write_d = be.write;
    interface read_d = ec.read;
    interface read_i = fe.read_inst;

    method Action hart_id(Bit#(TLog#(NUM_CPU)) in) = be.hart_id(in);



endmodule

endpackage
