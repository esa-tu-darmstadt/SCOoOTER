package Mem;

import Interfaces::*;
import Types::*;
import Inst_Types::*;
import FIFO::*;
import SpecialFIFOs::*;
import RWire::*;
import Debug::*;
import ClientServer::*;
import GetPut::*;

typedef struct {
    UInt#(TLog#(ROBDEPTH)) tag;
    union tagged {
        Bit#(XLEN) Result;
        ExceptionType Except;
        void None;
    } result;
    UInt#(XLEN) addr;
} LoadPipe deriving(Bits, FShow);

(* synthesize *)
module mkMem(MemoryUnitIFC);

FIFO#(Instruction) in <- mkPipelineFIFO();
FIFO#(Result) out <- mkPipelineFIFO();
RWire#(Result) out_valid <- mkRWire();

// store pipe
rule calculate_store if (in.first().opc == STORE);
    let inst = in.first(); in.deq();
    //$display("got store: ", fshow(inst));
    UInt#(XLEN) final_addr = unpack(inst.rs1.Operand + inst.imm);
    Maybe#(MemWr) write_req = tagged Invalid;
    if(inst.opc == STORE && inst.funct == W) begin
            write_req = tagged Valid MemWr {mem_addr : final_addr, data : inst.rs2.Operand, store_mask : 'b1111};
    end
    out.enq(Result {result : tagged Result 0, new_pc : tagged Invalid, tag : inst.tag, mem_wr : write_req});
endrule



FIFO#(LoadPipe) stage1 <- mkPipelineFIFO();
Wire#(LoadPipe) stage1_internal <- mkWire();
Wire#(LoadPipe) stage3_internal <- mkWire();
FIFO#(LoadPipe) stage2 <- mkPipelineFIFO();
FIFO#(Tuple2#(LoadPipe, Maybe#(MaskedWord))) stage3 <- mkPipelineFIFO();
FIFO#(LoadPipe) stage4 <- mkPipelineFIFO();
Wire#(UInt#(TLog#(ROBDEPTH))) request_ROB <- mkWire();
Wire#(Bool) response_ROB <- mkWire();
Wire#(UInt#(XLEN)) request_sb <- mkWire();
Wire#(Maybe#(MaskedWord)) response_sb <- mkWire();
FIFO#(UInt#(XLEN)) mem_read_request <- mkBypassFIFO();
FIFO#(UInt#(XLEN)) mem_read_response <- mkBypassFIFO();

//load pipe
rule calc_addr_and_check_ROB_load if (in.first().opc == LOAD);
    let inst = in.first();
    UInt#(XLEN) final_addr = unpack(inst.rs1.Operand + inst.imm);
    request_ROB <= inst.tag;

    stage1_internal <= LoadPipe {
        tag: inst.tag,
        result: tagged None,
        addr: final_addr
    };
endrule

rule check_rob_response if (in.first().opc == LOAD);
    let internal_state = stage1_internal;
    let rob_resp = response_ROB;
    if(!rob_resp) begin
        in.deq();
        stage1.enq(internal_state);
    end
endrule

rule wait_for_store_buffer;
    stage2.enq(stage1.first());
    stage1.deq();
endrule

rule check_fwd_path;
    let internal_struct = stage2.first();
    stage2.deq();
    request_sb <= internal_struct.addr;
    stage3_internal <= internal_struct;
endrule

rule check_fwd_path_resp;
    let struct_internal = stage3_internal;
    let response = response_sb;
    stage3.enq(tuple2(struct_internal, response));
endrule

rule request_axi_if_needed;
    let struct_internal = tpl_1(stage3.first());
    let fwd = tpl_2(stage3.first());

    if(fwd matches tagged Valid .mw &&& mw.store_mask == 'hf) begin
        stage3.deq();
        struct_internal.result = tagged Result mw.data;
        stage4.enq(struct_internal);
    end else
    if(fwd matches tagged Invalid) begin
        stage3.deq();
        stage4.enq(struct_internal);
        mem_read_request.enq(struct_internal.addr);
    end
endrule

rule collect_result_read_axi if(stage4.first().result matches tagged None);
    stage4.deq();
    mem_read_response.deq();

    let resp = mem_read_response.first();
    let internal_struct = stage4.first();


    out.enq(Result {result : tagged Result pack(resp), new_pc : tagged Invalid, tag : internal_struct.tag, mem_wr : tagged Invalid});
endrule

(* descending_urgency="collect_result_read_axi, collect_result_read_bypass, calculate_store" *)
rule collect_result_read_bypass if(stage4.first().result matches tagged Result .r);
     stage4.deq();
    let internal_struct = stage4.first();
    out.enq(Result {result : tagged Result pack(internal_struct.result.Result), new_pc : tagged Invalid, tag : internal_struct.tag, mem_wr : tagged Invalid});
endrule


rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);
endrule

interface FunctionalUnitIFC fu;
    method Action put(Instruction inst) = in.enq(inst);
    method Maybe#(Result) get() = out_valid.wget();
endinterface

interface Client check_rob;
    interface Get request;
        method ActionValue#(UInt#(TLog#(ROBDEPTH))) get();
            actionvalue
                return request_ROB;
            endactionvalue
        endmethod

    endinterface
    interface Put response;
        method Action put(Bool b) = response_ROB._write(b);
    endinterface
endinterface

interface Client check_store_buffer;
    interface Get request;
        method ActionValue#(UInt#(XLEN)) get();
            actionvalue
                return request_sb;
            endactionvalue
        endmethod

    endinterface
    interface Put response;
        method Action put(Maybe#(MaskedWord) b) = response_sb._write(b);
    endinterface
endinterface

interface Client read;
    interface Get request;
        method ActionValue#(Bit#(XLEN)) get();
            actionvalue
                mem_read_request.deq();
                return pack(mem_read_request.first());
            endactionvalue
        endmethod

    endinterface
    interface Put response;
        method Action put(Bit#(XLEN) b);
            mem_read_response.enq(unpack(b));
        endmethod
    endinterface
endinterface

endmodule


endpackage