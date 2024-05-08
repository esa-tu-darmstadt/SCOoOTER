package SCOOOTER_riscv;

/*

Toplevel module for a single core. Cores are combined into multicore systems by DAVE.

*/

import Vector::*;
import Interfaces::*;
import Types::*;
import Inst_Types::*;
import GetPut::*;
import Connectable :: *;
import Frontend::*;
import ExecCore::*;
import Backend::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkSCOOOTER_riscv(Top);

    // instantiate the three main components
    let fe <- mkFrontend();
    let ec <- mkExecCore();
    let be <- mkBackend();

    // connect BE to FE
    mkConnection(be.train, fe.train); // train predictors
    rule commit_to_fetch;
        fe.redirect(be.redirect_pc()); // redirect PC
    endrule


    // connect EC to BE
    mkConnection(ec.csr_write, be.csr_write); // csr writing
    mkConnection(ec.csr_read, be.csr_read); // csr reading
    mkConnection(be.read_registers, ec.read_committed); // register reading
    // pass result bus
    rule propagate_result_bus;
        be.res_bus(ec.res_bus());
    endrule
    rule commit_to_exec; // flush exec units with state
        ec.flush(Vector::map(isValid, be.redirect_pc()));
    endrule
    rule connect_rob_issue; // connect ROB feedback to ec
        ec.rob_free(be.rob_free());
        ec.rob_current_tail_idx(be.current_tail_idx());
    endrule
    rule connect_rob_issue2; // forward ROB reservations to BE
        let req = ec.get_reservation();
        uncurry(be.reserve)(req);
    endrule


    // connect EC to FE
    mkConnection(ec.decoded_inst, fe.decoded_inst); // instruction passing


    // wire interrupt signals to core
    Vector#(NUM_THREADS, Vector#(3, Wire#(Bool))) int_mask <- replicateM(replicateM(mkBypassWire()));
    rule push_int;
        be.int_flags(Vector::map(Vector::readVReg,int_mask));
    endrule

    // DExIE signals
    `ifdef DEXIE
        interface DExIEIfc dexie;
            method Action stall_signals(Bool control, Bool store);
                Bool memu_stall = control || store;
                Bool commit_stall = control;
                be.dexie_stall(commit_stall);
                ec.dexie_stall(memu_stall);
            endmethod
            method Vector#(ISSUEWIDTH, Maybe#(DexieReg)) regw = be.dexie.regw;
            method Vector#(ISSUEWIDTH, Maybe#(DexieCF)) cf = be.dexie.cf();
            interface memw = ec.dexie_memw();
        endinterface
    `endif

    // interrupt interface from external world
    method Action sw_int(Vector#(NUM_THREADS, Bool) b); for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) int_mask[i][2]._write(b[i]); endmethod
    method Action timer_int(Vector#(NUM_THREADS, Bool) b); for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) int_mask[i][1]._write(b[i]); endmethod
    method Action ext_int(Vector#(NUM_THREADS, Bool) b); for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) int_mask[i][0]._write(b[i]); endmethod

    // branch efficacy signals
    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br = be.correct_pred_br;
        method UInt#(XLEN) wrong_pred_br = be.wrong_pred_br;
        method UInt#(XLEN) correct_pred_j = be.correct_pred_j;
        method UInt#(XLEN) wrong_pred_j = be.wrong_pred_j;
    `endif

    // memory access
    interface write_d = ec.write;
    interface read_d = ec.read;
    interface read_i = fe.read_inst;

    // HART ID
    method Action hart_id(Bit#(TLog#(TMul#(NUM_CPU, NUM_THREADS))) in) = be.hart_id(in);

endmodule

endpackage
