package Div;

import Interfaces::*;
import Types::*;
import Inst_Types::*;
import FIFO::*;
import SpecialFIFOs::*;
import RWire::*;
import Debug::*;
import Divide::*;
import ClientServer::*;
import GetPut::*;

(* synthesize *)
module mkDiv(FunctionalUnitIFC);

FIFO#(Instruction) in <- mkPipelineFIFO();
FIFO#(Result) out <- mkPipelineFIFO();
RWire#(Result) out_valid <- mkRWire();

Server#(Tuple2#(UInt#(64),UInt#(XLEN)),Tuple2#(UInt#(XLEN),UInt#(XLEN))) unsigned_div <- mkDivider(1);
Server#(Tuple2#(Int#(64),Int#(XLEN)),Tuple2#(Int#(XLEN),Int#(XLEN))) signed_div <- mkSignedDivider(1);

FIFO#(Instruction) pending_results <- mkSizedFIFO(35); //latency of divider is 32 + 3

rule calculate;
    let inst = in.first(); in.deq();

    pending_results.enq(inst);

    dbg_print(ALU, $format("got instruction: ", fshow(inst)));

    UInt#(XLEN) op1_u = unpack(inst.rs1.Operand);
    UInt#(XLEN) op2_u = unpack(inst.rs2.Operand);
    Int#(XLEN) op1_s = unpack(inst.rs1.Operand);
    Int#(XLEN) op2_s = unpack(inst.rs2.Operand);

    if(inst.funct == DIV || inst.funct == REM) begin
        signed_div.request.put(tuple2(extend(op1_s), op2_s));
    end else
    if(inst.funct == DIVU || inst.funct == REMU) begin
        unsigned_div.request.put(tuple2(extend(op1_u), op2_u));
    end
endrule

rule read_result_signed if (pending_results.first().funct == DIV || pending_results.first().funct == REM);
    let inst = pending_results.first(); pending_results.deq();
    let resp <- signed_div.response.get();

    Int#(XLEN) result = case (inst.funct)  
        DIV: ( inst.rs2.Operand == 0 ? unpack('hffffffff)       : tpl_1(resp));
        REM: ( inst.rs2.Operand == 0 ? unpack(inst.rs1.Operand) : tpl_2(resp));
    endcase;
    
    dbg_print(ALU, $format("generated result: ", fshow(Result {result : tagged Result pack(result), new_pc : tagged Invalid, tag : inst.tag})));

    out.enq(Result {result : tagged Result pack(result), new_pc : tagged Invalid, tag : inst.tag, mem_wr : tagged Invalid});
endrule

rule read_result_unsigned if (pending_results.first().funct == DIVU || pending_results.first().funct == REMU);
    let inst = pending_results.first(); pending_results.deq();
    let resp <- unsigned_div.response.get();
    
    UInt#(XLEN) result = case (inst.funct)  
        DIVU: ( inst.rs2.Operand == 0 ? unpack('hffffffff)       : tpl_1(resp));
        REMU: ( inst.rs2.Operand == 0 ? unpack(inst.rs1.Operand) : tpl_2(resp));
    endcase;

    dbg_print(ALU, $format("generated result: ", fshow(Result {result : tagged Result pack(result), new_pc : tagged Invalid, tag : inst.tag})));

    out.enq(Result {result : tagged Result pack(result), new_pc : tagged Invalid, tag : inst.tag, mem_wr : tagged Invalid});
endrule

rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);

endrule

method Action put(Instruction inst);
    in.enq(inst);
endmethod

method Maybe#(Result) get() =
    out_valid.wget();
endmodule

endpackage