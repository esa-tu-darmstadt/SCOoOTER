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

(* synthesize *)
module mkDave(DaveIFC);
    

    let mem_arbiter <- mkMemoryArbiter();
    let inst_arbiter <- mkInstructionArbiter();

    Vector#(NUM_CPU, Top) cores <- replicateM(mkSCOOOTER_riscv());


    for(Integer i = 0; i < valueOf(NUM_CPU); i=i+1) begin
        mkConnection(inst_arbiter.reads[i], cores[i].read_i);
        mkConnection(mem_arbiter.reads[i], cores[i].read_d);
        mkConnection(mem_arbiter.writes[i], cores[i].write_d);
        rule propagate_hartid;
            cores[i].hart_id(fromInteger(i));
        endrule
    end

    for(Integer i = 1; i < valueOf(NUM_CPU); i=i+1) begin
        rule ignore_int;
            cores[i].sw_int(False);
            cores[i].timer_int(False);
            cores[i].ext_int(False);
        endrule
    end


    interface imem_axi = inst_arbiter.axi_r;
    interface dmem_axi_r = mem_arbiter.axi_r;
    interface dmem_axi_w = mem_arbiter.axi_w;

    method Action sw_int(Bool b) = cores[0].sw_int(b);
    method Action timer_int(Bool b) = cores[0].timer_int(b);
    method Action ext_int(Bool b) = cores[0].ext_int(b);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br = cores[0].correct_pred_br;
        method UInt#(XLEN) wrong_pred_br = cores[0].wrong_pred_br;
        method UInt#(XLEN) correct_pred_j = cores[0].correct_pred_j;
        method UInt#(XLEN) wrong_pred_j = cores[0].wrong_pred_j;
    `endif


endmodule

endpackage
