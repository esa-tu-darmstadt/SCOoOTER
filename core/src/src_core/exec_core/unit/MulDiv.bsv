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
function Bit#(32) two_complement_backward_32(Bit#(XLEN) op) = (op - 1) ^ 'hffffffff;
function Bit#(32) two_complement_forward_32(Bit#(32) op) = (op  ^ 'hffffffff) + 1;

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

// convert operands to unsigned operands and a flag indicating if the output will be negative
// incoming operands are accompanied by a flag indicating if they are signed or unsigned
function Tuple3#(Bit#(XLEN), Bit#(XLEN), Bool) operands_to_unsigned_tuple_32(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool) req);
    Bit#(XLEN) op1_u = extend(tpl_1(req));
            Bit#(XLEN) op2_u = extend(tpl_3(req));

            Bit#(XLEN) op1_s = op1_u[31] == 1 ? two_complement_backward_32(tpl_1(req)) : (tpl_1(req));
            Bit#(XLEN) op2_s = op2_u[31] == 1 ? two_complement_backward_32(tpl_3(req)) : (tpl_3(req));

            Bit#(XLEN) op1 = tpl_2(req) ? op1_s : op1_u;
            Bit#(XLEN) op2 = tpl_4(req) ? op2_s : op2_u;
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

// pipelined mul first creating partial results and then summing them
module mkPipelineMul(Server#(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool), Bit#(64)));
    
    FIFO#(Bit#(64)) out_f <- mkPipelineFIFO();
    FIFO#(Tuple2#(Vector#(32, Bit#(64)), Bool)) stage1_buf <- mkPipelineFIFO();
    FIFO#(Tuple2#(Vector#(16, Bit#(64)), Bool)) stage2_buf <- mkPipelineFIFO();
    FIFO#(Tuple2#(Vector#(08, Bit#(64)), Bool)) stage3_buf <-  mkPipelineFIFO();
    FIFO#(Tuple2#(Vector#(04, Bit#(64)), Bool)) stage4_buf <-  mkPipelineFIFO();
    FIFO#(Tuple2#(Vector#(02, Bit#(64)), Bool)) stage5_buf <-  mkPipelineFIFO();
    FIFO#(Tuple2#(Bit#(64), Bool)) stage6_buf <-              mkPipelineFIFO();
    FIFO#(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool)) incoming_request <- mkPipelineFIFO();
    FIFO#(Tuple3#(Bit#(64), Bit#(64), Bool)) stage0_buf <- mkPipelineFIFO();

    Vector#(6, Reg#(Bool)) require_invert <- replicateM(mkRegU());

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
        
        Vector#(32, Bit#(64)) new_values;

        for(Integer i = 0; i < 32; i=i+1) begin
            new_values[i] = ( op2[i] == 0 ? 0 : op1 << i );
        end
        
        stage1_buf.enq(tuple2(new_values, tpl_3(req)));
    endrule

    // build a sum tree
    rule stage_2;
        stage1_buf.deq();
        
        Vector#(16, Bit#(64)) new_values;
        
        for(Integer i = 0; i < 16; i = i+1) begin
            new_values[i] = tpl_1(stage1_buf.first())[2*i] + tpl_1(stage1_buf.first())[2*i+1];
        end
        
        stage2_buf.enq(tuple2(new_values, tpl_2(stage1_buf.first())));
    endrule

    rule stage_3;
        stage2_buf.deq();
        
        Vector#(8, Bit#(64)) new_values;
        
        for(Integer i = 0; i < 8; i = i+1) begin
            new_values[i] = tpl_1(stage2_buf.first())[2*i] + tpl_1(stage2_buf.first())[2*i+1];
        end
        
        stage3_buf.enq(tuple2(new_values, tpl_2(stage2_buf.first())));
    endrule

    rule stage_4;
        stage3_buf.deq();
        
        Vector#(4, Bit#(64)) new_values;
        
        for(Integer i = 0; i < 4; i = i+1) begin
            new_values[i] = tpl_1(stage3_buf.first())[2*i] + tpl_1(stage3_buf.first())[2*i+1];
        end
        
        stage4_buf.enq(tuple2(new_values, tpl_2(stage3_buf.first())));
    endrule

    rule stage_5;
        stage4_buf.deq();
        
        Vector#(2, Bit#(64)) new_values;
        
        for(Integer i = 0; i < 2; i = i+1) begin
            new_values[i] = tpl_1(stage4_buf.first())[2*i] + tpl_1(stage4_buf.first())[2*i+1];
        end
        
        stage5_buf.enq(tuple2(new_values, tpl_2(stage4_buf.first())));
    endrule

    rule stage_6;
        stage5_buf.deq();
        stage6_buf.enq( tuple2(tpl_1(stage5_buf.first())[0] + tpl_1(stage5_buf.first())[1], tpl_2(stage5_buf.first())) );
    endrule

    // invert final sum if necessary
    rule stage_7;
        let value = tpl_1(stage6_buf.first()); stage6_buf.deq();
        out_f.enq( tpl_2(stage6_buf.first()) ? two_complement_forward(value) : value);
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

// naive divider using BSV operator
// takes two operands, returns result and remainder
module mkNaiveDiv(Server#(Tuple3#(Bit#(XLEN),Bit#(XLEN),Bool),Tuple2#(Bit#(XLEN),Bit#(XLEN))));
    
    FIFOF#(Tuple2#(Bit#(XLEN),Bit#(XLEN))) out_f <- mkPipelineFIFOF();

    interface Put request;
        method Action put(Tuple3#(Bit#(XLEN),Bit#(XLEN),Bool) operands);
            let operands_unsigned = operands_to_unsigned_tuple_32(tuple4(tpl_1(operands), tpl_3(operands), tpl_2(operands), tpl_3(operands)));

            UInt#(XLEN) op1 = unpack(tpl_1(operands_unsigned));
            UInt#(XLEN) op2 = unpack(tpl_2(operands_unsigned));

            // hack as BlueSim crashes otherwise
            UInt#(XLEN) op2m = op2 == 0 ? 1 : op2;

            // calculate quotient and remainder
            UInt#(XLEN) result_div = op2 == 0 ?  'hffffffff : (op1/op2m);
            UInt#(XLEN) result_mod = op2 == 0 ? op1 : (op1%op2m);

            // calculate if sign inversion is needed anywhere
            let invert_r = tpl_3(operands_unsigned);
            let invert_rem_r = unpack(truncateLSB(tpl_1(operands))) && tpl_3(operands);

            // invert sign and provide result
            Bit#(XLEN) nom_out = invert_r ? two_complement_forward_32(truncate(pack(result_div))) : truncate(pack(result_div));
            Bit#(XLEN) res_out = invert_rem_r ? two_complement_forward_32(truncate(pack(result_mod))) : truncate(pack(result_mod));
            out_f.enq(tuple2(nom_out, res_out));
            
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(Tuple2#(Bit#(XLEN),Bit#(XLEN))) get();
            actionvalue
                out_f.deq();
                return out_f.first();
            endactionvalue
        endmethod
    endinterface
endmodule

// mul requiring multiple CPU cycles but allowing for higher clock speed
module mkMultiCycleDiv(Server#(Tuple3#(Bit#(XLEN),Bit#(XLEN),Bool),Tuple2#(Bit#(XLEN),Bit#(XLEN)))) provisos (
    Add#(2, XLEN, divlen),
    Log#(XLEN, dlen_log_t)
);
    
    FIFOF#(Tuple2#(Bit#(XLEN),Bit#(XLEN))) out_f <- mkPipelineFIFOF();
    
    Reg#(Int#(divlen)) nom <- mkRegU();
    Reg#(Int#(divlen)) den <- mkRegU();
    Reg#(Int#(divlen)) rem <- mkRegU();
    Reg#(UInt#(dlen_log_t)) cnt <- mkRegU();
    Reg#(Bool) busy_r <- mkReg(False);
    Reg#(Bool) invert_r <- mkRegU();
    Reg#(Bool) invert_rem_r <- mkRegU();

    rule compute if (busy_r == True);
        Int#(divlen) nom_loc = nom;
        Int#(divlen) rem_loc = rem;

        // new AQ calculation
        rem_loc = unpack({truncate(pack(rem_loc)),pack(nom_loc)[valueOf(XLEN)-1]});
        nom_loc = nom_loc<<1;

        // new rem calculation
        if(rem_loc >= 0) rem_loc = rem_loc-den;
        else             rem_loc = rem_loc+den;

        // update nominator
        nom_loc = unpack({truncateLSB(pack(nom_loc)), rem_loc>=0 ? 1'b1: 1'b0});

        // end condition
        if(cnt == 0) begin
            if(rem_loc<0) rem_loc = rem_loc+den;
            Bit#(XLEN) nom_out = invert_r ? two_complement_forward_32(truncate(pack(nom_loc))) : truncate(pack(nom_loc));
            Bit#(XLEN) rem_out = invert_rem_r ? two_complement_forward_32(truncate(pack(rem_loc))) : truncate(pack(rem_loc));
            out_f.enq(tuple2(nom_out, rem_out));
            busy_r <= False;
        end

        // update registers
        nom <= nom_loc;
        rem <= rem_loc;

        // decrement counter
        cnt <= cnt-1;
    endrule

    interface Put request;
        method Action put(Tuple3#(Bit#(XLEN),Bit#(XLEN),Bool) operands) if (busy_r == False && out_f.notFull());
            let operands_unsigned = operands_to_unsigned_tuple_32(tuple4(tpl_1(operands), tpl_3(operands), tpl_2(operands), tpl_3(operands)));
            busy_r <= True;
            nom <= unpack(zeroExtend(tpl_1(operands_unsigned)));
            den <= unpack(zeroExtend(tpl_2(operands_unsigned)));
            rem <= 0;
            cnt <= fromInteger(valueOf(XLEN)-1);
            invert_r <= tpl_3(operands_unsigned);
            invert_rem_r <= unpack(truncateLSB(tpl_1(operands))) && tpl_3(operands);
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(Tuple2#(Bit#(XLEN),Bit#(XLEN))) get();
            actionvalue
                out_f.deq();
                return out_f.first();
            endactionvalue
        endmethod
    endinterface

    
endmodule

typedef struct {
    Int#(TAdd#(XLEN, 2)) nom;
    Int#(TAdd#(XLEN, 2)) den;
    Int#(TAdd#(XLEN, 2)) rem;
    Bool invert;
    Bool invert_rem;
} DivState deriving(Bits, FShow);

// mul requiring multiple CPU cycles but allowing for higher clock speed
module mkPipelineDiv(Server#(Tuple3#(Bit#(XLEN),Bit#(XLEN),Bool),Tuple2#(Bit#(XLEN),Bit#(XLEN)))) provisos (
    Add#(2, XLEN, divlen),
    Log#(XLEN, dlen_log_t),
    Add#(1, XLEN, vlen_t)
);
    
    FIFOF#(Tuple2#(Bit#(XLEN),Bit#(XLEN))) out_f <- mkPipelineFIFOF();
    
    Vector#(vlen_t, FIFO#(DivState)) states_v <- replicateM(mkPipelineFIFO());

    for(Integer i = 0; i < valueOf(XLEN); i=i+1) begin
        rule compute;

            let state = states_v[i].first();
            states_v[i].deq();
            

            Int#(divlen) nom_loc = state.nom;
            Int#(divlen) rem_loc = state.rem;

            // new AQ calculation
            rem_loc = unpack({truncate(pack(rem_loc)),pack(nom_loc)[valueOf(XLEN)-1]});
            nom_loc = nom_loc<<1;

            // new rem calculation
            if(rem_loc >= 0) rem_loc = rem_loc-state.den;
            else             rem_loc = rem_loc+state.den;

            // update nominator
            nom_loc = unpack({truncateLSB(pack(nom_loc)), rem_loc>=0 ? 1'b1: 1'b0});

            // update registers
            state.nom = nom_loc;
            state.rem = rem_loc;

            //pass on stuff
            states_v[i+1].enq(state);
        endrule
    end

    rule finalize;
        let state = Vector::last(states_v).first();
        Vector::last(states_v).deq();

        if(state.rem<0) state.rem = state.rem+state.den;
        Bit#(XLEN) nom_out = state.invert ? two_complement_forward_32(truncate(pack(state.nom))) : truncate(pack(state.nom));
        Bit#(XLEN) rem_out = state.invert_rem ? two_complement_forward_32(truncate(pack(state.rem))) : truncate(pack(state.rem));
        out_f.enq(tuple2(nom_out, rem_out));
    endrule

    interface Put request;
        method Action put(Tuple3#(Bit#(XLEN),Bit#(XLEN),Bool) operands);
            let operands_unsigned = operands_to_unsigned_tuple_32(tuple4(tpl_1(operands), tpl_3(operands), tpl_2(operands), tpl_3(operands)));

            states_v[0].enq(DivState {
                nom : unpack(zeroExtend(tpl_1(operands_unsigned))),
                den : unpack(zeroExtend(tpl_2(operands_unsigned))),
                rem : 0,
                invert : tpl_3(operands_unsigned),
                invert_rem : unpack(truncateLSB(tpl_1(operands))) && tpl_3(operands)
            });
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(Tuple2#(Bit#(XLEN),Bit#(XLEN))) get();
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

// types needed for mul/div inflight storage
typedef struct {
    UInt#(TLog#(ROBDEPTH)) tag;
    Bool div_by_zero;
    Bool is_rem;
} DivPipe deriving(Bits);

typedef struct {
    UInt#(TLog#(ROBDEPTH)) tag;
    Bool is_mulh;
} MulPipe deriving(Bits);

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkMulDiv(FunctionalUnitIFC);

// in and out buffers for this FU
FIFO#(InstructionIssue) in <- mkPipelineFIFO();
FIFO#(Result) out <- mkPipelineFIFO();
RWire#(Result) out_valid <- mkRWire();

//Select correct multipliers and dividers based on configured strategy
Server#(Tuple3#(Bit#(XLEN),Bit#(XLEN),Bool),Tuple2#(Bit#(XLEN),Bit#(XLEN))) div <- case (valueOf(MUL_DIV_STRATEGY)) 
    2: mkPipelineDiv();
    1: mkMultiCycleDiv();
    0: mkNaiveDiv();
    endcase;
Server#(Tuple4#(Bit#(XLEN), Bool, Bit#(XLEN), Bool), Bit#(64)) mul <- case (valueOf(MUL_DIV_STRATEGY))
    2: mkPipelineMul();
    1: mkMultiCycleMul();
    0: mkNaiveMul();
    endcase;

// buffers for in flight instructions
FIFO#(DivPipe) pending_results_div <- mkSizedFIFO(32);
FIFO#(MulPipe) pending_results_mul <- mkSizedFIFO(9); //at most 9 mul are in flight at once

// this rule distributes the incoming instructions upon the multipliers and dividers
// based on calculation type
rule calculate;
    let inst = in.first(); in.deq();

    dbg_print(MulDiv, $format("got instruction: ", fshow(inst)));

    Bit#(XLEN) op1 = unpack(inst.rs1.Operand);
    Bit#(XLEN) op2 = unpack(inst.rs2.Operand);

    // distribute the instructions
    if(inst.funct == DIV || inst.funct == REM) begin
        div.request.put(tuple3(op1, op2, True));
        pending_results_div.enq(DivPipe {tag: inst.tag, div_by_zero: (inst.rs2.Operand == 0), is_rem: (inst.funct == REM || inst.funct == REMU)});
    end else
    if(inst.funct == DIVU || inst.funct == REMU) begin
        div.request.put(tuple3(op1, op2, False));
        pending_results_div.enq(DivPipe {tag: inst.tag, div_by_zero: (inst.rs2.Operand == 0), is_rem: (inst.funct == REM || inst.funct == REMU)});
    end else
    if (inst.funct == MUL || inst.funct == MULHU) begin
        mul.request.put(tuple4(op1, False, op2, False));
        pending_results_mul.enq(MulPipe {tag: inst.tag, is_mulh: (inst.funct == MULHU)});
    end else
    if (inst.funct == MULH) begin
        mul.request.put(tuple4(op1, True, op2, True));
        pending_results_mul.enq(MulPipe {tag: inst.tag, is_mulh: True});
    end else
    if (inst.funct == MULHSU) begin
        mul.request.put(tuple4(op1, True, op2, False));
        pending_results_mul.enq(MulPipe {tag: inst.tag, is_mulh: True});
    end
endrule

// those rules read results from the multipliers and dividers
// and dequeue inflight instructions

rule read_result_div;
    let inst = pending_results_div.first(); pending_results_div.deq();
    let resp <- div.response.get();

    // catch edge case that the divisor is zero and select div or rem
    Bit#(XLEN) result = (inst.is_rem ?
        (tpl_2(resp)) :
        ( inst.div_by_zero ? unpack('hffffffff) : tpl_1(resp)));
    
    dbg_print(MulDiv, $format("generated result: ", fshow(Result {result : tagged Result result, new_pc : tagged Invalid, tag : inst.tag})));

    out.enq(Result {result : tagged Result result, new_pc : tagged Invalid, tag : inst.tag});
endrule

(* descending_urgency = "read_result_div, read_result_mul" *)
rule read_result_mul;
    let inst = pending_results_mul.first(); pending_results_mul.deq();
    let resp <- mul.response.get();
    
    Bit#(XLEN) result = !inst.is_mulh ? resp[31:0] : resp[63:32];

    dbg_print(MulDiv, $format("generated result: ", fshow(Result {result : tagged Result result, new_pc : tagged Invalid, tag : inst.tag})));

    out.enq(Result {result : tagged Result result, new_pc : tagged Invalid, tag : inst.tag});
endrule

// output the current result
rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);
endrule

method Action put(InstructionIssue inst) = in.enq(inst);
method Maybe#(Result) get() = out_valid.wget();
endmodule

endpackage
