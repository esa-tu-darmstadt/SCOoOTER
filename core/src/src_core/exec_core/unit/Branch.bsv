package Branch;

import Interfaces::*;
import Types::*;
import Inst_Types::*;
import FIFO::*;
import SpecialFIFOs::*;
import RWire::*;
import Debug::*;

(* synthesize *)
module mkBranch(FunctionalUnitIFC);

FIFO#(Instruction) in_f <- mkPipelineFIFO();
FIFO#(Result) out_f <- mkPipelineFIFO();
RWire#(Result) out_valid_w <- mkRWire();

rule set_valid;
    out_valid_w.wset(out_f.first());
    out_f.deq();
endrule

Wire#(Bool) condition_w <- mkWire();
Wire#(Bit#(XLEN)) target_w <- mkWire();


rule test_condition;
    let inst = in_f.first();

    UInt#(XLEN) op1_u = unpack(inst.rs1.Operand);
    UInt#(XLEN) op2_u = unpack(inst.rs2.Operand);
    Int#(XLEN)  op1_s = unpack(inst.rs1.Operand);
    Int#(XLEN)  op2_s = unpack(inst.rs2.Operand);

    Bool condition = case (inst.opc)
        BRANCH: case (inst.funct)
                    BEQ: (op1_u == op2_u);
                    BNE: (op1_u != op2_u);
                    BLT: (op1_s < op2_s);
                    BLTU:(op1_u < op2_u);
                    BGE: (op1_s >= op2_s);
                    BGEU:(op1_u >= op2_u);
                endcase
        default: True;
    endcase;

    condition_w <= condition;
endrule

rule calculate_target;
    let inst = in_f.first();
    dbg_print(BRU, $format("got instruction: ", fshow(inst)));

    Bit#(XLEN) current_pc = inst.pc;
    Bit#(XLEN) imm = inst.imm;

    Bit#(XLEN) target = case (inst.opc)
        JAL, BRANCH:   (current_pc + imm);
        JALR:          ((inst.rs1.Operand + imm) & 'hfffffffe);
    endcase;

    target_w <= target;
    dbg_print(BRU, $format("calculated target: ", target));
endrule

rule build_response_packet;
    let inst = in_f.first(); in_f.deq();
    Maybe#(Bit#(XLEN)) target = condition_w ? tagged Valid target_w : tagged Invalid;
    let resp = Result {
        tag:    inst.tag,
        result: (inst.exception matches tagged Valid .e ? tagged Except e :
                  target matches tagged Valid .a &&& a[1:0] != 0 ? tagged Except MISALIGNED_ADDR
                  : tagged Result (inst.pc+4)),
        new_pc: target,
        mem_wr : tagged Invalid
    };
    dbg_print(BRU, $format("produced result: ", fshow(resp)));
    out_f.enq(resp);
endrule

method Action put(Instruction inst);
    in_f.enq(inst);
endmethod

method Maybe#(Result) get() =
    out_valid_w.wget();

endmodule

endpackage