package MulDiv;

/*
  FU for multipla-divide operations
*/

import Interfaces::*;
import Types::*;
import Inst_Types::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import RWire::*;
import Debug::*;
import Divide::*;
import ClientServer::*;
import GetPut::*;
import Vector::*;

//////////////////////////////////////////////////////////////////////////////////
// MUL implementations
//////////////////////////////////////////////////////////////////////////////////

// convert between absolute value and twos complement for negative integers
function Bit#(64) two_complement_backward(Bit#(XLEN) op) = (signExtend(op) - 1) ^ 'hffffffffffffffff;
function Bit#(64) two_complement_forward(Bit#(64) op) = (op  ^ 'hffffffffffffffff) + 1;

// convert operands to unsigned operands and a flag indicating if the output will be negative
// incoming operands are accompanied by a flag indicating if they are signed or unsigned
function Tuple3#(Bit#(64), Bit#(64), Bool) operands_to_unsigned_tuple(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool) req);
    Bit#(64) op1_u = extend(tpl_1(req));
            Bit#(64) op2_u = extend(tpl_3(req));

            Bit#(64) op1_s = op1_u[31] == 1 ? two_complement_backward(tpl_1(req)) : extend(tpl_1(req));
            Bit#(64) op2_s = op2_u[31] == 1 ? two_complement_backward(tpl_3(req)) : extend(tpl_3(req));

            Bit#(64) op1 = tpl_2(req) ? op1_s : op1_u;
            Bit#(64) op2 = tpl_4(req) ? op2_s : op2_u;
            Bool must_negate = (tpl_2(req) && (op1_u[31] == 1)) != ((tpl_4(req) && (op2_u[31] == 1)));

            return tuple3(op1, op2, must_negate);
endfunction

// simple mul using the bluespec operator
// slow implementation, only as a counter-example
module mkNaiveMul(Server#(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool), Bit#(64)));
    
    FIFO#(Bit#(64)) out_f <- mkPipelineFIFO();

    interface Put request;
        method Action put(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool) req);
            let operands = operands_to_unsigned_tuple(req);
            Bit#(64) result = tpl_1(operands) * tpl_2(operands);
            out_f.enq(tpl_3(operands) ? two_complement_forward(result) : result);
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(Bit#(64)) get();
            actionvalue
                out_f.deq();
                return out_f.first();
            endactionvalue
        endmethod
    endinterface
endmodule

// mul requiring multiple CPU cycles but allowing for higher clock speed
module mkMultiCycleMul(Server#(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool), Bit#(64)));
    
    FIFOF#(Bit#(64)) out_f <- mkPipelineFIFOF();
    Reg#(Bool) busy_r <- mkReg(False);
    Reg#(Bit#(64)) op1_r <- mkRegU();
    Reg#(Bit#(64)) op2_r <- mkRegU();
    Reg#(Bool) invert_r <- mkRegU();
    Reg#(Bit#(64)) result_r <- mkRegU();

    rule compute if (busy_r == True);
        if(op2_r[0] == 1) begin
            result_r <= result_r + op1_r;
        end
        op2_r <= op2_r >> 1;
        op1_r <= op1_r << 1;
        if(op2_r == 0 || op1_r == 0) begin
            out_f.enq(invert_r ? two_complement_forward(result_r) : result_r);
            busy_r <= False;
        end
    endrule

    interface Put request;
        method Action put(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool) req) if (busy_r == False && out_f.notFull());
            let operands = operands_to_unsigned_tuple(req);
            busy_r <= True;
            op1_r <= tpl_1(operands);
            op2_r <= tpl_2(operands);
            invert_r <= tpl_3(operands);
            result_r <= 0;
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(Bit#(64)) get();
            actionvalue
                out_f.deq();
                return out_f.first();
            endactionvalue
        endmethod
    endinterface
    
endmodule

// pipelined mul first creating partial results and then suming them
module mkPipelineMul(Server#(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool), Bit#(64)));
    
    FIFO#(Bit#(64)) out_f <- mkPipelineFIFO();
    Vector#(32, FIFO#(Bit#(64))) stage1_buf <- replicateM(mkPipelineFIFO());
    Vector#(16, FIFO#(Bit#(64))) stage2_buf <- replicateM(mkPipelineFIFO());
    Vector#(8, FIFO#(Bit#(64))) stage3_buf <-  replicateM(mkPipelineFIFO());
    Vector#(4, FIFO#(Bit#(64))) stage4_buf <-  replicateM(mkPipelineFIFO());
    Vector#(2, FIFO#(Bit#(64))) stage5_buf <-  replicateM(mkPipelineFIFO());
    FIFO#(Bit#(64)) stage6_buf <-                         mkPipelineFIFO();
    FIFO#(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool)) incoming_request <- mkPipelineFIFO();
    FIFO#(Tuple3#(Bit#(64), Bit#(64), Bool)) stage0_buf <- mkPipelineFIFO();

    Vector#(6, Reg#(Bool)) require_invert <- replicateM(mkRegU());

    // advance the invert result flag through the stages
    rule advance_invert;
        for(Integer i = 5; i > 0; i=i-1)
            require_invert[i] <= require_invert[i-1];
    endrule

    // convert operands to unsigned and invert result flag
    rule stage_0;
        let req = incoming_request.first(); incoming_request.deq();
        let operands = operands_to_unsigned_tuple(req);
        stage0_buf.enq(operands);
    endrule

    // create partial sums
    rule stage_1;
        let req = stage0_buf.first(); stage0_buf.deq();
        Bit#(64) op1 = extend(tpl_1(req));
        Bit#(XLEN) op2 = truncate(tpl_2(req));
        require_invert[0] <= tpl_3(req);

        for(Integer i = 0; i < 32; i=i+1) begin
            stage1_buf[i].enq( op2[i] == 0 ? 0 : op1 << i );
        end
    endrule

    // build a sum tree
    rule stage_2;
        for(Integer i = 0; i < 32; i = i+1) stage1_buf[i].deq();
        for(Integer i = 0; i < 16; i = i+1) begin
            stage2_buf[i].enq( stage1_buf[2*i].first() + stage1_buf[2*i+1].first() );
        end
    endrule

    rule stage_3;
        for(Integer i = 0; i < 16; i = i+1) stage2_buf[i].deq();
        for(Integer i = 0; i < 8; i = i+1) begin
            stage3_buf[i].enq( stage2_buf[2*i].first() + stage2_buf[2*i+1].first() );
        end
    endrule

    rule stage_4;
        for(Integer i = 0; i < 8; i = i+1) stage3_buf[i].deq();
        for(Integer i = 0; i < 4; i = i+1) begin
            stage4_buf[i].enq( stage3_buf[2*i].first() + stage3_buf[2*i+1].first() );
        end
    endrule

    rule stage_5;
        for(Integer i = 0; i < 4; i = i+1) stage4_buf[i].deq();
        for(Integer i = 0; i < 2; i = i+1) begin
            stage5_buf[i].enq( stage4_buf[2*i].first() + stage4_buf[2*i+1].first() );
        end
    endrule

    rule stage_6;
        for(Integer i = 0; i < 2; i = i+1) stage5_buf[i].deq();
        stage6_buf.enq( stage5_buf[0].first() + stage5_buf[1].first() );
    endrule

    // invert final sum if necessary
    rule stage_7;
        let value = stage6_buf.first(); stage6_buf.deq();
        out_f.enq( require_invert[5] ? two_complement_forward(value) : value);
    endrule

    interface Put request;
        method Action put(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool) req);
            incoming_request.enq(req);
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(Bit#(64)) get();
            actionvalue
                out_f.deq();
                return out_f.first();
            endactionvalue
        endmethod
    endinterface
    
endmodule

///////////////////////////////////////////////////////////////////
// Div Implementations
///////////////////////////////////////////////////////////////////
// we mostly use the BSV builtin ones, only naive is implemented here

// naive divider using BSV operator (unsigned)
// takes two operands, returns result and remainder
module mkNaiveDivUnsigned(Server#(Tuple2#(UInt#(64),UInt#(XLEN)),Tuple2#(UInt#(XLEN),UInt#(XLEN)))); 
    FIFO#(Tuple2#(UInt#(XLEN),UInt#(XLEN))) out_f <- mkPipelineFIFO();
    Wire#(UInt#(XLEN)) op1_w <- mkWire();
    Wire#(UInt#(XLEN)) op2_w <- mkWire();

    interface Put request;
        method Action put(Tuple2#(UInt#(64),UInt#(XLEN)) req);
            UInt#(XLEN) op1 = truncate(tpl_1(req));
            UInt#(XLEN) op2 = tpl_2(req);

            // we could also just return ? if the operand is 0 because this will be 
            // caught later but bluesim crashes if we do so
            UInt#(XLEN) result_div =  op2 == 0 ? 'hffffffff : (op1/op2);
            UInt#(XLEN) result_mod =  op2 == 0 ? op1        : (op1%op2);

            out_f.enq(tuple2(result_div, result_mod));
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(Tuple2#(UInt#(XLEN),UInt#(XLEN))) get();
            actionvalue
                out_f.deq();
                return out_f.first();
            endactionvalue
        endmethod
    endinterface
endmodule

// naive divider using BSV operator (signed)
// takes two operands, returns result and remainder
module mkNaiveDivSigned(Server#(Tuple2#(Int#(64),Int#(XLEN)),Tuple2#(Int#(XLEN),Int#(XLEN)))); 
    FIFO#(Tuple2#(Int#(XLEN),Int#(XLEN))) out_f <- mkPipelineFIFO();

    interface Put request;
        method Action put(Tuple2#(Int#(64),Int#(XLEN)) req);
            Int#(XLEN) op1  = truncate(tpl_1(req));
            Int#(XLEN) op2  = tpl_2(req);

            // hack as BlueSim crashes otherwise
            Int#(XLEN) op2m = tpl_2(req) == 0 ? 1 : tpl_2(req);

            Int#(XLEN) result_div = op2 == 0 ?  -1 : (op1/op2m);
            Int#(XLEN) result_mod = op2 == 0 ? op1 : (op1%op2m);

            out_f.enq(tuple2(result_div, result_mod));
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(Tuple2#(Int#(XLEN),Int#(XLEN))) get();
            actionvalue
                out_f.deq();
                return out_f.first();
            endactionvalue
        endmethod
    endinterface
endmodule

///////////////////////////////////////////////////////////////////
// Real FU module
///////////////////////////////////////////////////////////////////

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkMulDiv(FunctionalUnitIFC);

// in and out buffers for this FU
FIFO#(Instruction) in <- mkPipelineFIFO();
FIFO#(Result) out <- mkPipelineFIFO();
RWire#(Result) out_valid <- mkRWire();

//Select correct multipliers and dividers based on configured strategy
Server#(Tuple2#(UInt#(64),UInt#(XLEN)),Tuple2#(UInt#(XLEN),UInt#(XLEN))) unsigned_div <- case (valueOf(MUL_DIV_STRATEGY)) 
    2: mkDivider(4);
    1: mkNonPipelinedDivider(4);
    0: mkNaiveDivUnsigned();
    endcase;

Server#(Tuple2#(Int#(64),Int#(XLEN)),Tuple2#(Int#(XLEN),Int#(XLEN))) signed_div <- case (valueOf(MUL_DIV_STRATEGY)) 
    2: mkSignedDivider(4);
    1: mkNonPipelinedSignedDivider(4);
    0: mkNaiveDivSigned();
    endcase;
    
Server#(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool), Bit#(64)) mul <- case (valueOf(MUL_DIV_STRATEGY))
    2: mkPipelineMul();
    1: mkMultiCycleMul();
    0: mkNaiveMul();
    endcase;

// buffers for in flight instructions
FIFO#(Instruction) pending_results_sign <- mkSizedFIFO(35); //latency of divider is 32 + 3
FIFO#(Instruction) pending_results_nosign <- mkSizedFIFO(35); //latency of divider is 32 + 3
FIFO#(Instruction) pending_results_mul <- mkSizedFIFO(9); //at most 9 mul are in flight at once

// this rule distributes the incoming instructions upon the multipliers and dividers
// based on calculation type
rule calculate;
    let inst = in.first(); in.deq();

    dbg_print(MulDiv, $format("got instruction: ", fshow(inst)));

    // generate signed, unsigned and bit variants of the operands
    Bit#(XLEN) op1 = unpack(inst.rs1.Operand);
    Bit#(XLEN) op2 = unpack(inst.rs2.Operand);
    UInt#(XLEN) op1_u = unpack(inst.rs1.Operand);
    UInt#(XLEN) op2_u = unpack(inst.rs2.Operand);
    Int#(XLEN) op1_s = unpack(inst.rs1.Operand);
    Int#(XLEN) op2_s = unpack(inst.rs2.Operand);

    // distribute the instructions
    if(inst.funct == DIV || inst.funct == REM) begin
        signed_div.request.put(tuple2(extend(op1_s), op2_s));
        pending_results_sign.enq(inst);
    end else
    if(inst.funct == DIVU || inst.funct == REMU) begin
        unsigned_div.request.put(tuple2(extend(op1_u), op2_u));
        pending_results_nosign.enq(inst);
    end else
    if (inst.funct == MUL || inst.funct == MULHU) begin
        mul.request.put(tuple4(op1, False, op2, False));
        pending_results_mul.enq(inst);
    end else
    if (inst.funct == MULH) begin
        mul.request.put(tuple4(op1, True, op2, True));
        pending_results_mul.enq(inst);
    end else
    if (inst.funct == MULHSU) begin
        mul.request.put(tuple4(op1, True, op2, False));
        pending_results_mul.enq(inst);
    end
endrule

// those rules read results from the multipliers and dividers
// and dequeue inflight instructions

rule read_result_signed_div;
    let inst = pending_results_sign.first(); pending_results_sign.deq();
    let resp <- signed_div.response.get();

    // catch edge case that the divisor is zero
    Int#(XLEN) result = case (inst.funct)  
        DIV: ( inst.rs2.Operand == 0 ? unpack('hffffffff)       : tpl_1(resp));
        REM: ( inst.rs2.Operand == 0 ? unpack(inst.rs1.Operand) : tpl_2(resp));
    endcase;
    
    dbg_print(MulDiv, $format("generated result: ", fshow(Result {result : tagged Result pack(result), new_pc : tagged Invalid, tag : inst.tag})));

    out.enq(Result {result : tagged Result pack(result), new_pc : tagged Invalid, tag : inst.tag});
endrule

rule read_result_unsigned_div;
    let inst = pending_results_nosign.first(); pending_results_nosign.deq();
    let resp <- unsigned_div.response.get();
    
    // catch edge case that the divisor is zero
    UInt#(XLEN) result = case (inst.funct)  
        DIVU: ( inst.rs2.Operand == 0 ? unpack('hffffffff)       : tpl_1(resp));
        REMU: ( inst.rs2.Operand == 0 ? unpack(inst.rs1.Operand) : tpl_2(resp));
    endcase;

    dbg_print(MulDiv, $format("generated result: ", fshow(Result {result : tagged Result pack(result), new_pc : tagged Invalid, tag : inst.tag})));

    out.enq(Result {result : tagged Result pack(result), new_pc : tagged Invalid, tag : inst.tag});
endrule

(* descending_urgency = "read_result_signed_div, read_result_unsigned_div, read_result_mul" *)
rule read_result_mul;
    let inst = pending_results_mul.first(); pending_results_mul.deq();
    let resp <- mul.response.get();
    
    Bit#(XLEN) result = inst.funct == MUL ? resp[31:0] : resp[63:32];

    dbg_print(MulDiv, $format("generated result: ", fshow(Result {result : tagged Result result, new_pc : tagged Invalid, tag : inst.tag})));

    out.enq(Result {result : tagged Result result, new_pc : tagged Invalid, tag : inst.tag});
endrule

// output the current result
rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);
endrule

method Action put(Instruction inst) = in.enq(inst);
method Maybe#(Result) get() = out_valid.wget();
endmodule

endpackage