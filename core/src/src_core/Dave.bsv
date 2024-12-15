package Dave;
import MulDiv::*;
import MemoryArbiter::*;
import InstructionArbiter::*;
import SCOOOTER_riscv::*;
import Interfaces::*;
import Connectable::*;
import Vector::*;
import Config::*;
import Types::*;

/*

DAVE implements arbitration of memory accesses from multiple cores.

*/

(* synthesize, clock_prefix = "clk_i" *)
module mkDave(DaveIFC);
    
    // instantiate arbiters
    let mem_arbiter <- mkMemoryArbiter();
    let inst_arbiter <- mkInstructionArbiter();

    // instantiate cores
    Vector#(NUM_CPU, Top) cores <- replicateM(mkSCOOOTER_riscv());

    // connect arbiters to cores
    for(Integer i = 0; i < valueOf(NUM_CPU); i=i+1) begin
        mkConnection(inst_arbiter.reads[i], cores[i].read_i);
        mkConnection(mem_arbiter.reads[i], cores[i].read_d);
        mkConnection(mem_arbiter.writes[i], cores[i].write_d);
        // provide HART id to cores
        rule propagate_hartid;
            cores[i].hart_id(fromInteger(i*valueOf(NUM_THREADS)));
        endrule
    end

    // output DExIE iface
    `ifdef DEXIE
        Vector#(NUM_CPU, DExIEIfc) dexie_loc;
        for (Integer i = 0; i < valueOf(NUM_CPU); i=i+1)
            dexie_loc[i] = cores[i].dexie;
        interface DExIEIfc dexie = dexie_loc;
    `endif

    // connection to memories
    interface imem_r = inst_arbiter.imem_r;
    interface dmem_r = mem_arbiter.dmem_r;
    interface dmem_w = mem_arbiter.dmem_w;

    // interrupt flags
    method Action sw_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) b); for(Integer i = 0; i < valueOf(NUM_CPU); i=i+1) cores[i].sw_int(b[i]); endmethod
    method Action timer_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) b); for(Integer i = 0; i < valueOf(NUM_CPU); i=i+1) cores[i].timer_int(b[i]); endmethod
    method Action ext_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) b); for(Integer i = 0; i < valueOf(NUM_CPU); i=i+1) cores[i].ext_int(b[i]); endmethod

    // branch efficacy information
    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br = cores[0].correct_pred_br;
        method UInt#(XLEN) wrong_pred_br = cores[0].wrong_pred_br;
        method UInt#(XLEN) correct_pred_j = cores[0].correct_pred_j;
        method UInt#(XLEN) wrong_pred_j = cores[0].wrong_pred_j;
    `endif


endmodule
endpackage
