package Mem;

/*
  FU for memory accesses
*/

import Interfaces::*;
import Types::*;
import Inst_Types::*;
import FIFO::*;
import SpecialFIFOs::*;
import RWire::*;
import Debug::*;
import ClientServer::*;
import GetPut::*;
import Vector::*;

// struct for access width
typedef enum {
        BYTE,
        HALF,
        WORD
} Width deriving(Bits, Eq, FShow);

// struct for load pipeline stages
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
    UInt#(EPOCH_WIDTH) epoch;
    Bool amo;
    AmoType amo_t;
    Bit#(XLEN) amo_modifier;
    Bool aq;
    Bool rl;
    Bool mispredicted;
    UInt#(TLog#(NUM_THREADS)) thread_id;
} LoadPipe deriving(Bits, FShow);

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkMem(MemoryUnitIFC) provisos (
    Log#(ROBDEPTH, rob_idx_t)
);

// incoming instruction
FIFO#(Instruction) in <- mkPipelineFIFO();

// outgoing result
FIFO#(Result) out <- mkPipelineFIFO();
// wrap outgoing result as maybe to avoid blocking behavior
RWire#(Result) out_valid <- mkRWire();
// outgoing memory write
FIFO#(MemWr) out_wr <- mkBypassFIFO();

// local epoch for tossing wrong-path instructions
// this reduces bus pressure 
Vector#(NUM_THREADS, Reg#(UInt#(EPOCH_WIDTH))) epoch_r <- replicateM(mkReg(0));

// ROB head ID
Wire#(UInt#(rob_idx_t)) rob_head <- mkBypassWire();


// Aq / Rl handling
Reg#(Bool) aq_r <- mkReg(False);
Wire#(Bool) store_queue_empty_w <- mkBypassWire();
Wire#(Bool) store_queue_full_w <- mkBypassWire();

function Bool check_misalign(Bit#(2) mask, Width width) = case (width)
    BYTE: False;
    HALF: (mask[0] != 0);
    WORD: (mask != 0);
endcase;

// STORE HANDLING

// single-cycle calculation
// real write occurs in storebuffer after successful commit
rule calculate_store if (!store_queue_full_w && in.first().opc == STORE && !aq_r && (rob_head == in.first().tag || valueOf(ROBDEPTH) == 1) && in.first().epoch == epoch_r[in.first().thread_id]);
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

    Width width = case (inst.funct)
        W: WORD;
        H: HALF;
        B: BYTE;
    endcase;

    dbg_print(Mem, $format("instruction:  ", fshow(inst)));
    
    // produce result
    let local_result = Result {result : ((check_misalign(truncate(pack(final_addr)), width)) ? tagged Except AMO_ST_MISALIGNED : tagged Result 0) , new_pc : tagged Invalid, tag : inst.tag 
        `ifdef RVFI 
            , mem_addr: final_addr
        `endif
        };
    if (inst.exception matches tagged Valid .e) local_result.result = tagged Except e;
    out.enq(local_result);
    out_wr.enq(MemWr {mem_addr : axi_addr, data : wr_data, store_mask : mask});
endrule

rule calculate_store_flush if (in.first().opc == STORE && in.first().epoch != epoch_r[in.first().thread_id]);
    let inst = in.first(); in.deq();

    // produce result
    Result local_result = ?;
    local_result.tag = inst.tag;
    out.enq(local_result);
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

// request/response buffers
FIFO#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType)))) mem_rd_or_amo_request <- mkBypassFIFO();
FIFO#(Bit#(XLEN)) mem_rd_or_amo_response <- mkBypassFIFO();

// STAGE 1: calculate address and check if a memory access is pending in ROB

// inter-clock buffers
Wire#(LoadPipe) stage1_internal <- mkWire();
Wire#(UInt#(TLog#(ROBDEPTH))) request_ROB <- mkWire();
Wire#(Bool) response_ROB <- mkWire();
//output to next stage
FIFO#(LoadPipe) stage1 <- mkPipelineFIFO();

rule calc_addr_and_check_ROB_load if ( (in.first().opc == LOAD || in.first().opc == AMO) && in.first().epoch == epoch_r[in.first().thread_id] && !aq_r);

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
        aq: inst.aq,
        rl: inst.rl,
        mispredicted: False,
        thread_id: inst.thread_id
    };
    dbg_print(Mem, $format("instruction:  ", fshow(inst)));
endrule

// check ROB response, if the instruction is clear, commence execution
// otherwise do not dequeue it and try again next cycle
Wire#(UInt#(XLEN)) request_sb <- mkWire();
rule check_rob_response if (((in.first().opc == LOAD || in.first().opc == AMO) && in.first().epoch == epoch_r[in.first().thread_id]));
    let internal_state = stage1_internal;
    in.deq();
    stage1.enq(internal_state);
    dbg_print(AMO, $format("rob passed:  ", fshow(internal_state)));
    if (internal_state.amo) aq_r <= internal_state.aq;
    request_sb <= unpack({pack(internal_state.addr)[31:2], 2'b00});
endrule

// toss instructions with wrong epoch
rule flush_invalid_loads if ((in.first().opc == LOAD || in.first().opc == AMO) && in.first().epoch != epoch_r[in.first().thread_id]);
    let inst = in.first(); in.deq();
    stage1.enq(LoadPipe { tag: inst.tag, mispredicted: True});
endrule

// STAGE 2: forward data from store buffer

// intra-clock buffer
Wire#(Maybe#(MaskedWord)) response_sb <- mkWire();
// output to next stage
FIFO#(Tuple2#(LoadPipe, Maybe#(MaskedWord))) stage2 <- mkPipelineFIFO();

// raise request to store buffer
// get response from store buffer
rule check_fwd_path_resp  if (stage1.first().epoch == epoch_r[stage1.first().thread_id] && !stage1.first().mispredicted);
    let struct_internal = stage1.first();
    let response = response_sb;
    // if the response matches our load/store mask, move into next stage
    // otherwise wait
    if (!struct_internal.amo && (!isValid(response) || (response.Valid.store_mask & struct_internal.load_mask) == struct_internal.load_mask)) begin
        stage2.enq(tuple2(struct_internal, response));
        stage1.deq();
        dbg_print(Mem, $format("store buffer:  ", fshow(struct_internal), " ", fshow(response)));
    end
    // if AMO, no fwd is allowed
    else if (struct_internal.amo && !isValid(response)) begin
        stage2.enq(tuple2(struct_internal, response));
        stage1.deq();
        dbg_print(AMO, $format("store buffer passed:  ", fshow(struct_internal)));
    end else begin
        request_sb <= unpack({pack(struct_internal.addr)[31:2], 2'b00}); // re-request fwd
        dbg_print(AMO, $format("store buffer retry:  ", fshow(struct_internal), fshow(response)));
    end
endrule

// remove wrong-epoch instructions from pipeline
rule flush_invalid_fwds if (stage1.first().epoch != epoch_r[stage1.first().thread_id] || stage1.first().mispredicted);
    let internal_struct = stage1.first(); stage1.deq();
    if(internal_struct.aq) aq_r <= False;
    internal_struct.mispredicted = True;
    stage2.enq(tuple2(internal_struct, ?));
endrule


// STAGE 3: ask AXI or use fwd data

// output to next stage
FIFO#(LoadPipe) stage3 <- mkPipelineFIFO();

rule request_axi_if_needed if (tpl_1(stage2.first()).epoch == epoch_r[tpl_1(stage2.first()).thread_id] && !tpl_1(stage2.first()).mispredicted);
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
            let addr = struct_internal.addr & 'hfffffffc;
            if (addr < fromInteger(valueOf(BRAMSIZE)) || addr >= fromInteger(2*valueOf(BRAMSIZE)))
                    addr = fromInteger(valueOf(BRAMSIZE));
            mem_rd_or_amo_request.enq(tuple2(pack(addr), tagged Invalid));
        end
    end
    else if(
            (rob_head == struct_internal.tag || valueOf(ROBDEPTH) == 1) && // wait until we are sure AMO is correct-path
            (struct_internal.rl ? store_queue_empty_w : True) // on a release, stall the AMO such that pending writes get through
            ) begin
                dbg_print(AMO, $format("request:  ", fshow(struct_internal)));
                stage2.deq();
                stage3.enq(struct_internal);
                mem_rd_or_amo_request.enq(tuple2(pack(struct_internal.addr), tagged Valid tuple2(struct_internal.amo_modifier, struct_internal.amo_t)));
            end
endrule

// remove wrong-epoch instructions
rule flush_invalid_axi_rq if (tpl_1(stage2.first()).epoch != epoch_r[tpl_1(stage2.first()).thread_id] || tpl_1(stage2.first()).mispredicted);
    let internal_struct = tpl_1(stage2.first()); stage2.deq();
    if(internal_struct.aq) aq_r <= False;
    internal_struct.mispredicted = True;
    stage3.enq(internal_struct);
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
    return Result {result : tagged Result result, new_pc : tagged Invalid, tag : internal_struct.tag};
endfunction

// rules to collect the result from all available sources

// collect result from bypass
rule collect_result_read_bypass if(!stage3.first().amo &&& stage3.first().result matches tagged Result .r &&& !stage3.first().mispredicted);
    stage3.deq();
    let internal_struct = stage3.first();
    let resp = internal_struct.result.Result;

    let result = internal_struct_and_data_to_result(internal_struct, resp);

    // create misalign exception
    if(check_misalign(truncate(pack(internal_struct.addr)), internal_struct.width)) begin
        result.result = tagged Except MISALIGNED_LOAD;
    end

    //RVFI
    `ifdef RVFI
        result.mem_addr = internal_struct.addr;
    `endif

    dbg_print(Mem, $format("read (byp):  ", fshow(result)));
    out.enq(result);
endrule

// collect response from AXI if needed
rule collect_result_read if(stage3.first().result matches tagged None &&& !stage3.first().mispredicted);
    stage3.deq();
    mem_rd_or_amo_response.deq();
    let resp = pack(mem_rd_or_amo_response.first());
    let internal_struct = stage3.first();

    if(internal_struct.aq && internal_struct.amo) aq_r <= False;

    let result = internal_struct_and_data_to_result(internal_struct, resp);

    if(stage3.first().amo) dbg_print(AMO, $format("response:  ", fshow(internal_struct), fshow(resp)));

    // create misalign exception
    if(check_misalign(truncate(pack(internal_struct.addr)), internal_struct.width)) begin
        result.result = tagged Except (stage3.first().amo ? AMO_ST_MISALIGNED : MISALIGNED_LOAD);
    end

    dbg_print(Mem, $format("read (axi):  ", fshow(result)));

    //RVFI
    `ifdef RVFI
        result.mem_addr = internal_struct.addr;
    `endif

    out.enq(result);
endrule

rule collect_result_mispredict if(stage3.first().mispredicted);
    stage3.deq();
    let internal_struct = stage3.first();
    if(internal_struct.aq) aq_r <= False;

    //RVFI
    out.enq(Result {
        result : tagged Result 0,
        new_pc : tagged Invalid,
        tag : internal_struct.tag
        `ifdef RVFI 
            , mem_addr: internal_struct.addr
        `endif
    });
endrule

// generate output (and define in which urgency results shall be propagated)
(* preempts="calculate_store, (collect_result_mispredict, collect_result_read, collect_result_read_bypass)" *)
rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);
endrule

// FU iface
interface FunctionalUnitIFC fu;
    method Action put(Instruction inst);
        dbg_print(Mem, $format("got from RS:  ", fshow(inst)));
        in.enq(inst);
    endmethod
    method Maybe#(Result) get() = out_valid.wget();
endinterface

// forwarding from store buffer
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

interface Client request;
    interface Get request = toGet(mem_rd_or_amo_request);
    interface Put response = toPut(mem_rd_or_amo_response);
endinterface

// epoch handling
method Action flush(Vector#(NUM_THREADS, Bool) flags);
    for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
        if(flags[i]) epoch_r[i] <= epoch_r[i] + 1;
endmethod

// input current rob ID
method Action current_rob_id(UInt#(rob_idx_t) idx) = rob_head._write(idx);

// test if sb is empty
method Action store_queue_empty(Bool b) = store_queue_empty_w._write(b);

method Action store_queue_full(Bool b) = store_queue_full_w._write(b);

interface Get write = toGet(out_wr);

endmodule


endpackage
