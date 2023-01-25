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

typedef enum {
        BYTE,
        HALF,
        WORD
} Width deriving(Bits, Eq, FShow);

typedef struct {
    UInt#(TLog#(ROBDEPTH)) tag;
    union tagged {
        Bit#(XLEN) Result;
        ExceptionType Except;
        void None;
    } result;
    UInt#(XLEN) addr;
    Bit#(TDiv#(XLEN, 8)) load_mask;
    Width width;
    Bool sign;
} LoadPipe deriving(Bits, FShow);

(* synthesize *)
module mkMem(MemoryUnitIFC);

FIFO#(Instruction) in <- mkPipelineFIFO();
FIFO#(Result) out <- mkPipelineFIFO();
RWire#(Result) out_valid <- mkRWire();

// store pipe
rule calculate_store if (in.first().opc == STORE);
    let inst = in.first(); in.deq();
    ////$display("got store: ", fshow(inst));
    UInt#(XLEN) final_addr = unpack(inst.rs1.Operand + inst.imm);
    UInt#(XLEN) axi_addr = final_addr & 'hfffffffc;

    let raw_data = inst.rs2.Operand;

    Bit#(XLEN) wr_data = case (inst.funct)
        W: raw_data;
        H: (pack(final_addr)[1] == 0 ? raw_data : raw_data << 16);
        B: (raw_data << (pack(final_addr)[1] == 0 ? 0 : 16) << (pack(final_addr)[0] == 0 ? 0 : 8));
    endcase;

    Bit#(TDiv#(XLEN, 8)) mask = case (inst.funct)
        W: 'b1111;
        H: (pack(final_addr)[1] == 0 ? 'b0011 : 'b1100);
        B: (1 << pack(final_addr)[1:0]);
    endcase;

    Maybe#(MemWr) write_req = tagged Valid MemWr {mem_addr : axi_addr, data : wr_data, store_mask : mask};
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

    Bit#(TDiv#(XLEN, 8)) mask = case (inst.funct)
        W: 'b1111;
        H, HU: (pack(final_addr)[1] == 0 ? 'b0011 : 'b1100);
        B, BU: (1 << pack(final_addr)[1:0]);
    endcase;

    stage1_internal <= LoadPipe {
        tag: inst.tag,
        result: tagged None,
        addr: final_addr,
        load_mask: mask,
        width: case (inst.funct)
            B, BU: BYTE;
            H, HU: HALF;
            W: WORD;
            endcase,
        sign: (inst.funct != BU && inst.funct != HU)
    };
    //$display(fshow(inst), fshow(pack(final_addr)));
endrule

rule check_rob_response if (in.first().opc == LOAD);
    let internal_state = stage1_internal;
    let rob_resp = response_ROB;
    if(!rob_resp) begin
        in.deq();
        stage1.enq(internal_state);
        //$display("ROB succeeded: ", fshow(internal_state));
    end
endrule

rule wait_for_store_buffer;
    stage2.enq(stage1.first());
    stage1.deq();
endrule

rule check_fwd_path;
    let internal_struct = stage2.first();
    request_sb <= internal_struct.addr & 'hfffffffc;
    stage3_internal <= internal_struct;
    //$display("request fwd path: ", fshow(internal_struct));
endrule

rule check_fwd_path_resp;
    let struct_internal = stage3_internal;
    let response = response_sb;
    //$display("got fwd path: ", fshow(response));
    if (!isValid(response) || (response.Valid.store_mask & struct_internal.load_mask) == struct_internal.load_mask) begin
        stage3.enq(tuple2(struct_internal, response));
        stage2.deq();
        //$display("feedback success: ", fshow(response), fshow(struct_internal));
    end
endrule

rule request_axi_if_needed;
    let struct_internal = tpl_1(stage3.first());
    let fwd = tpl_2(stage3.first());

    if(fwd matches tagged Valid .mw &&& (mw.store_mask & struct_internal.load_mask) == struct_internal.load_mask) begin
        stage3.deq();
        struct_internal.result = tagged Result mw.data;
        stage4.enq(struct_internal);
        //$display("use fwd: ", fshow(struct_internal));
    end else
    if(fwd matches tagged Invalid) begin
        stage3.deq();
        stage4.enq(struct_internal);
        mem_read_request.enq(struct_internal.addr & 'hfffffffc);
        //$display("use AXI: ", fshow(struct_internal));
    end
endrule

rule collect_result_read_axi if(stage4.first().result matches tagged None);
    stage4.deq();
    mem_read_response.deq();

    let resp = pack(mem_read_response.first());
    let internal_struct = stage4.first();

    let addr = pack(internal_struct.addr);
    Bit#(16) halfword = case (addr[1])
        0: resp[15:0];
        1: resp[31:16];
        endcase;
    Bit#(8) byteword = case (addr[1:0])
        0: resp[7:0];
        1: resp[15:8];
        2: resp[23:16];
        3: resp[31:24];
    endcase;

    // do sign stuff
    Bit#(XLEN) result = case (internal_struct.width)
        WORD: resp;
        HALF: (internal_struct.sign ? signExtend(halfword) : zeroExtend(halfword));
        BYTE: (internal_struct.sign ? signExtend(byteword) : zeroExtend(byteword));
    endcase;

    dbg_print(Mem, $format("read:  ", fshow(Result {result : tagged Result result, new_pc : tagged Invalid, tag : internal_struct.tag, mem_wr : tagged Invalid})));
    out.enq(Result {result : tagged Result result, new_pc : tagged Invalid, tag : internal_struct.tag, mem_wr : tagged Invalid});
endrule

(* descending_urgency="collect_result_read_axi, collect_result_read_bypass, calculate_store" *)
rule collect_result_read_bypass if(stage4.first().result matches tagged Result .r);
     stage4.deq();
    let internal_struct = stage4.first();
    let resp = internal_struct.result.Result;

    let addr = pack(internal_struct.addr);
    Bit#(16) halfword = case (addr[1])
        0: resp[15:0];
        1: resp[31:16];
        endcase;
    Bit#(8) byteword = case (addr[1:0])
        0: resp[7:0];
        1: resp[15:8];
        2: resp[23:16];
        3: resp[31:24];
    endcase;

    // do sign stuff
    Bit#(XLEN) result = case (internal_struct.width)
        WORD: resp;
        HALF: (internal_struct.sign ? signExtend(halfword) : zeroExtend(halfword));
        BYTE: (internal_struct.sign ? signExtend(byteword) : zeroExtend(byteword));
    endcase;

    dbg_print(Mem, $format("read (fwd):", fshow(Result {result : tagged Result result, new_pc : tagged Invalid, tag : internal_struct.tag, mem_wr : tagged Invalid}) ));
    out.enq(Result {result : tagged Result result, new_pc : tagged Invalid, tag : internal_struct.tag, mem_wr : tagged Invalid});
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
                let addr = mem_read_request.first();
                if (addr < fromInteger(valueOf(BRAMSIZE)) || addr >= fromInteger(2*valueOf(BRAMSIZE)))
                    addr = fromInteger(valueOf(BRAMSIZE));
                return pack(addr);
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