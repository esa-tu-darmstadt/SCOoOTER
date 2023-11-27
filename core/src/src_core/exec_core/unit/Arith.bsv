package Arith;

/*
  FU for integer instructions
*/

import Interfaces::*;
import Types::*;
import Inst_Types::*;
import FIFO::*;
import SpecialFIFOs::*;
import RWire::*;
import Debug::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkArith(FunctionalUnitIFC);

// FIFOs for input and output
FIFO#(Instruction) in <- mkPipelineFIFO();
FIFO#(Result) out <- mkPipelineFIFO();
// RWire to always produce an output
RWire#(Result) out_valid <- mkRWire();

// transform an instruction into a result
rule calculate;
    let inst = in.first(); in.deq();

    dbg_print(ALU, $format("got instruction: ", fshow(inst)));

    let op1 = case (inst.opc)
        LUI: 0;
        AUIPC: {inst.pc, 2'b00};
        OPIMM, OP: inst.rs1.Operand;
    endcase;

    let op2 = case (inst.opc)
        LUI, AUIPC, OPIMM: inst.imm;
        OP: inst.rs2.Operand;
    endcase;

    UInt#(XLEN) op1_u = unpack(op1);
    UInt#(XLEN) op2_u = unpack(op2);
    Int#(XLEN) op1_s = unpack(op1);
    Int#(XLEN) op2_s = unpack(op2);

    let result = case (inst.funct)
        NONE, ADD: pack(op1 + op2); //do not care about sign
        SLT: pack(op1_s < op2_s ? 1 : 0);
        SLTU: pack(op1_u < op2_u ? 1 : 0);
        AND: (op1 & op2);
        OR: (op1 | op2);
        XOR: (op1 ^ op2);
        SRL: (op1 >> op2[4:0]);
        SLL: truncate(op1 << op2[4:0]);
        SRA: pack(op1_s >> op2[4:0]);
        SUB: (op1 - op2);
    endcase;

    let res = Result {
        result : (inst.exception matches tagged Valid .e ? tagged Except e : tagged Result result),
        new_pc : tagged Invalid,
        tag : inst.tag
    };

    dbg_print(ALU, $format("generated result: ", fshow(res)));

    out.enq(res);
endrule

// write the result to the output wire
rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);
endrule

// in and out functions
method Action put(Instruction inst) = in.enq(inst);
method Maybe#(Result) get() = out_valid.wget();
endmodule

endpackage