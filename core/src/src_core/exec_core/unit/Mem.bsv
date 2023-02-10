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
    UInt#(XLEN) epoch;
    Bool amo;
    AmoType amo_t;
    Bit#(XLEN) amo_modifier;
    Bool aq;
} LoadPipe deriving(Bits, FShow);

(* synthesize *)
module mkMem(MemoryUnitIFC) provisos (
    Log#(ROBDEPTH, rob_idx_t)
);

// incoming instruction
FIFO#(Instruction) in <- mkPipelineFIFO();

// outgoing result
FIFO#(Result) out <- mkPipelineFIFO();
// wrap outgoing result as maybe to avoid blocking behavior
RWire#(Result) out_valid <- mkRWire();

// local epoch for tossing wrong-path instructions
// this reduces bus pressure 
Reg#(UInt#(XLEN)) epoch_r <- mkReg(0);

// ROB head ID
Wire#(UInt#(rob_idx_t)) rob_head <- mkBypassWire();


// Aq / Rl handling
Reg#(Bool) aq_r <- mkReg(False);


// STORE HANDLING

// single-cycle calculation
// real write occurs in storebuffer after successful commit
rule calculate_store if (in.first().opc == STORE && !aq_r);
    let inst = in.first(); in.deq();

    // calculate final access address
    UInt#(XLEN) final_addr = unpack(inst.rs1.Operand + inst.imm);
    // AXI addresses entire word, therefore remove lower two bits
    UInt#(XLEN) axi_addr = final_addr & 'hfffffffc;

    // word provided for storage
    let raw_data = inst.rs2.Operand;

    // move bytes and half-words to the correct position in the memory word
    Bit#(XLEN) wr_data = case (inst.funct)
        W: raw_data;
        H: (raw_data << (pack(final_addr)[1] == 0 ? 0 : 16));
        B: (raw_data << (pack(final_addr)[1] == 0 ? 0 : 16) << (pack(final_addr)[0] == 0 ? 0 : 8));
    endcase;

    // calculate store mask for STRB AXI signal
    Bit#(TDiv#(XLEN, 8)) mask = case (inst.funct)
        W: 'b1111;
        H: ('b0011 << (pack(final_addr)[1] == 0 ? 0 : 2));
        B: (1 << pack(final_addr)[1:0]);
    endcase;
    
    // produce result
    out.enq(Result {result : tagged Result 0, new_pc : tagged Invalid, tag : inst.tag, write : tagged Mem MemWr {mem_addr : axi_addr, data : wr_data, store_mask : mask}});
endrule


// helper functions

function AmoType op_function_to_amo_type(OpFunction ofc);
    return case (ofc)
        LR: LR;
        SC: SC;
        SWAP: SWAP;
        MIN: MIN;
        MAX: MAX;
        MINU: MINU;
        MAXU: MAXU;
        ADD: ADD;
        XOR: XOR;
        OR: OR;
        AND: AND;
    endcase;
endfunction


// LOAD / AMO HANDLING

// STAGE 1: calculate address and check if a memory access is pending in ROB

// inter-clock buffers
Wire#(LoadPipe) stage1_internal <- mkWire();
Wire#(UInt#(TLog#(ROBDEPTH))) request_ROB <- mkWire();
Wire#(Bool) response_ROB <- mkWire();
//output to next stage
FIFO#(LoadPipe) stage1 <- mkPipelineFIFO();

rule calc_addr_and_check_ROB_load if ( (in.first().opc == LOAD || in.first().opc == AMO) && in.first().epoch == epoch_r && !aq_r);

    // get instruction, do not deq here as we do this only on success for ROB request
    let inst = in.first();
    // calculate address to which the store is pending
    UInt#(XLEN) final_addr = unpack(inst.rs1.Operand + inst.imm);
    // send a request to ROB (this will be acknowledged in the same clock cycle)
    request_ROB <= inst.tag;

    // calculate load mask
    Bit#(TDiv#(XLEN, 8)) mask = case (inst.funct)
        W: 'b1111;
        H, HU: ('b0011 << (pack(final_addr)[1] == 0 ? 0 : 2));
        B, BU: (1 << pack(final_addr)[1:0]);
    endcase;

    if (inst.opc == AMO) aq_r <= inst.aq;

    // fill internal data structure for load pipeline
    stage1_internal <= LoadPipe {
        tag: inst.tag,
        result: tagged None,
        addr: inst.opc == AMO ? unpack(inst.rs1.Operand) : final_addr,
        load_mask: mask,
        width: case (inst.funct)
            B, BU: BYTE;
            H, HU: HALF;
            W: WORD;
            endcase,
        sign: (inst.funct != BU && inst.funct != HU),
        epoch: inst.epoch,
        amo: (inst.opc == AMO),
        amo_t: op_function_to_amo_type(inst.funct),
        amo_modifier: inst.rs2.Operand,
        aq: inst.aq
    };
    dbg_print(Mem, $format("instruction:  ", fshow(inst)));
endrule

// check ROB response, if the instruction is clear, commence execution
// otherwise do not dequeue it and try again next cycle
rule check_rob_response if ((in.first().opc == LOAD || in.first().opc == AMO) && in.first().epoch == epoch_r);
    let internal_state = stage1_internal;
    let rob_resp = response_ROB;
    if(!rob_resp) begin
        in.deq();
        stage1.enq(internal_state);
        dbg_print(AMO, $format("rob passed:  ", fshow(internal_state)));
        
    end
endrule

// toss instructions with wrong epoch
rule flush_invalid_loads if ((in.first().opc == LOAD || in.first().opc == AMO) && in.first().epoch != epoch_r);
    let inst = in.first(); in.deq();
    out.enq(Result {result : tagged Result 0, new_pc : tagged Invalid, tag : inst.tag, write : tagged None});
endrule

// STAGE 2: forward data from store buffer

// intra-clock buffer
Wire#(LoadPipe) stage2_internal <- mkWire();
Wire#(UInt#(XLEN)) request_sb <- mkWire();
Wire#(Maybe#(MaskedWord)) response_sb <- mkWire();
// output to next stage
FIFO#(Tuple2#(LoadPipe, Maybe#(MaskedWord))) stage2 <- mkPipelineFIFO();

// raise request to store buffer
rule check_fwd_path if (stage1.first().epoch == epoch_r);
    let internal_struct = stage1.first();
    request_sb <= unpack({pack(internal_struct.addr)[31:2], 2'b00});
    stage2_internal <= internal_struct;
endrule

// get response from store buffer
rule check_fwd_path_resp  if (stage1.first().epoch == epoch_r);
    let struct_internal = stage2_internal;
    let response = response_sb;
    // if the response matches our load/store mask, move into next stage
    // otherwise wait
    if (!struct_internal.amo && (!isValid(response) || (response.Valid.store_mask & struct_internal.load_mask) == struct_internal.load_mask)) begin
        stage2.enq(tuple2(struct_internal, response));
        stage1.deq();
    end
    // if AMO, no fwd is allowed
    if (struct_internal.amo && !isValid(response)) begin
        stage2.enq(tuple2(struct_internal, response));
        stage1.deq();
        dbg_print(AMO, $format("store buffer passed:  ", fshow(struct_internal)));
    end
endrule

// remove wrong-epoch instructions from pipeline
rule flush_invalid_fwds if (stage1.first().epoch != epoch_r);
    let internal_struct = stage1.first(); stage1.deq();
    if(internal_struct.aq) aq_r <= False;
    out.enq(Result {result : tagged Result 0, new_pc : tagged Invalid, tag : internal_struct.tag, write : tagged None});
endrule


// STAGE 3: ask AXI or use fwd data

// inter-clock buffers
FIFO#(UInt#(XLEN)) mem_read_request <- mkBypassFIFO();
FIFO#(UInt#(XLEN)) mem_read_response <- mkBypassFIFO();
// output to next stage
FIFO#(LoadPipe) stage3 <- mkPipelineFIFO();
// output to mem arbiter
FIFO#(Tuple3#(Bit#(XLEN), Bit#(XLEN), AmoType)) amo_request <- mkBypassFIFO();
FIFO#(Bit#(XLEN)) amo_response <- mkBypassFIFO();

rule request_axi_if_needed if (tpl_1(stage2.first()).epoch == epoch_r);
    let struct_internal = tpl_1(stage2.first());
    let fwd = tpl_2(stage2.first());

    if(!struct_internal.amo) begin
        // use fwd path if matching
        if(fwd matches tagged Valid .mw) begin
            stage2.deq();
            struct_internal.result = tagged Result mw.data;
            stage3.enq(struct_internal);
        end else
        // ask AXI if no fwd
        if(fwd matches tagged Invalid) begin
            stage2.deq();
            stage3.enq(struct_internal);
            mem_read_request.enq(struct_internal.addr & 'hfffffffc);
        end
    end
    else if(rob_head == struct_internal.tag || valueOf(ROBDEPTH) == 1) begin
        dbg_print(AMO, $format("request:  ", fshow(struct_internal)));
        stage2.deq();
        stage3.enq(struct_internal);
        amo_request.enq(tuple3(pack(struct_internal.addr), struct_internal.amo_modifier, struct_internal.amo_t));
    end
endrule

// remove wrong-epoch instructions
rule flush_invalid_axi_rq if (tpl_1(stage2.first()).epoch != epoch_r);
    let internal_struct = tpl_1(stage2.first()); stage2.deq();
    if(internal_struct.aq) aq_r <= False;
    out.enq(Result {result : tagged Result 0, new_pc : tagged Invalid, tag : internal_struct.tag, write : tagged None});
endrule

// STAGE 4: collect result

function Result internal_struct_and_data_to_result(LoadPipe internal_struct, Bit#(XLEN) data);
    let addr = pack(internal_struct.addr);

    // produce half-words and bytes
    Bit#(16) halfword = case (addr[1])
        0: data[15:0];
        1: data[31:16];
        endcase;
    Bit#(8) byteword = case (addr[1:0])
        0: data[7:0];
        1: data[15:8];
        2: data[23:16];
        3: data[31:24];
    endcase;

    // select correct width and extend sign where needed
    Bit#(XLEN) result = case (internal_struct.width)
        WORD: data;
        HALF: (internal_struct.sign ? signExtend(halfword) : zeroExtend(halfword));
        BYTE: (internal_struct.sign ? signExtend(byteword) : zeroExtend(byteword));
    endcase;

    // produce result
    return Result {result : tagged Result result, new_pc : tagged Invalid, tag : internal_struct.tag, write : tagged None};
endfunction

// collect response from AXI if needed
rule collect_result_read_axi if(!stage3.first().amo &&& stage3.first().result matches tagged None);
    stage3.deq();
    mem_read_response.deq();

    let resp = pack(mem_read_response.first());
    let internal_struct = stage3.first();

    let result = internal_struct_and_data_to_result(internal_struct, resp);

    dbg_print(Mem, $format("read:  ", fshow(result)));

    out.enq(result);
endrule

// collect result from bypass
rule collect_result_read_bypass if(!stage3.first().amo &&& stage3.first().result matches tagged Result .r);
    stage3.deq();
    let internal_struct = stage3.first();
    let resp = internal_struct.result.Result;

    let result = internal_struct_and_data_to_result(internal_struct, resp);

    dbg_print(Mem, $format("read:  ", fshow(result)));
    out.enq(result);
endrule

// collect AMO result
rule collect_result_read_amo if(stage3.first().amo);
    stage3.deq();
    let internal_struct = stage3.first();
    let result = amo_response.first();
    amo_response.deq();

    if(internal_struct.aq) aq_r <= False;

    dbg_print(AMO, $format("got result:  ", fshow(result), " ", fshow(internal_struct)));
    out.enq(Result {result : tagged Result result, new_pc : tagged Invalid, tag : internal_struct.tag, write : tagged None});
endrule






// generate output (and define in which urgency results shall be propagated)
(* descending_urgency="collect_result_read_amo, collect_result_read_axi, collect_result_read_bypass, flush_invalid_axi_rq, flush_invalid_fwds, flush_invalid_loads, calculate_store" *)
rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);
endrule

interface FunctionalUnitIFC fu;
    method Action put(Instruction inst) = in.enq(inst);
    method Maybe#(Result) get() = out_valid.wget();
endinterface

// Request/Response interfaces

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

interface Client amo;
    interface Get request;
        method ActionValue#(Tuple3#(Bit#(XLEN), Bit#(XLEN), AmoType)) get();
            actionvalue
                amo_request.deq();
                return amo_request.first();
            endactionvalue
        endmethod

    endinterface
    interface Put response;
        method Action put(Bit#(XLEN) b);
            amo_response.enq(b);
        endmethod
    endinterface
endinterface

// epoch handling

method Action flush();
    epoch_r <= epoch_r + 1;
endmethod

method Action current_rob_id(UInt#(rob_idx_t) idx);
    rob_head <= idx;
endmethod

endmodule


endpackage
