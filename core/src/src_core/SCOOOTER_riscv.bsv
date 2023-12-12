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
import ArianeRegFile::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkSCOOOTER_riscv(Top) provisos(
        Mul#(XLEN, IFUINST, ifuwidth),
        Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
        Log#(issuewidth_pad_t, issuewidth_log_t),
        Log#(NUM_CPU, idx_cpu_t)
    );

    let fe <- mkFrontend();
    let ec <- mkExecCore();
    let be <- mkBackend();

    mkConnection(be.train, fe.train);

    mkConnection(ec.csr_write, be.csr_write);


    mkConnection(be.read_registers, ec.read_committed);

    rule propagate_result_bus;
        be.res_bus(ec.res_bus());
    endrule



    mkConnection(ec.csr_read, be.csr_read);

    Wire#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) evo_wire <- mkWire();

    mkConnection(ec.decoded_inst, fe.decoded_inst);

    rule flush_prints;
        $fflush();
    endrule

    rule commit_to_fetch;
        ec.flush(Vector::map(isValid, be.redirect_pc()));
        fe.redirect(be.redirect_pc());
    endrule

    rule connect_rob_issue;
        ec.rob_free(be.rob_free());
        ec.rob_current_idx(be.current_idx());
        ec.rob_current_tail_idx(be.current_tail_idx());
    endrule

    rule connect_rob_issue2;
        let req = ec.get_reservation();
        uncurry(be.reserve)(req);
    endrule

    Vector#(NUM_THREADS, Vector#(3, Wire#(Bool))) int_mask <- replicateM(replicateM(mkBypassWire()));
    rule push_int;
        be.int_flags(Vector::map(Vector::readVReg,int_mask));
    endrule

    // interrupts
    method Action sw_int(Vector#(NUM_THREADS, Bool) b); for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) int_mask[i][2]._write(b[i]); endmethod
    method Action timer_int(Vector#(NUM_THREADS, Bool) b); for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) int_mask[i][1]._write(b[i]); endmethod
    method Action ext_int(Vector#(NUM_THREADS, Bool) b); for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) int_mask[i][0]._write(b[i]); endmethod

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br = be.correct_pred_br;
        method UInt#(XLEN) wrong_pred_br = be.wrong_pred_br;
        method UInt#(XLEN) correct_pred_j = be.correct_pred_j;
        method UInt#(XLEN) wrong_pred_j = be.wrong_pred_j;
    `endif

    interface write_d = ec.write;
    interface read_d = ec.read;
    interface read_i = fe.read_inst;

    method Action hart_id(Bit#(TLog#(TMul#(NUM_CPU, NUM_THREADS))) in) = be.hart_id(in);

    `ifdef DEXIE
        interface DExIETraceIfc dexie;
            method Vector#(ISSUEWIDTH, Maybe#(DexieReg)) regw = be.dexie.regw;
            method Vector#(ISSUEWIDTH, Maybe#(DexieCF)) cf = be.dexie.cf();
            interface memw = ec.dexie_memw();
        endinterface
    `endif

endmodule

endpackage
