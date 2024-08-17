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
import Decode::*;
import MemoryDecoder::*;

// struct for load pipeline stages
// the struct holds data to-be-passed between stages
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
FIFO#(InstructionIssue) in <- mkPipelineFIFO();

// outgoing result
FIFO#(Result) out <- mkPipelineFIFO();
// wrap outgoing result as maybe to avoid blocking behavior
RWire#(Result) out_valid <- mkRWire();
// outgoing memory write
FIFO#(MemWr) out_wr <- mkBypassFIFO();

// local epoch for tossing wrong-path instructions during speculation
Vector#(NUM_THREADS, Reg#(UInt#(EPOCH_WIDTH))) epoch_r <- replicateM(mkReg(0));

// ROB head ID
Wire#(UInt#(rob_idx_t)) rob_head <- mkBypassWire();

// Atomics handling
Reg#(Bool) aq_r <- mkReg(False);
PulseWire clear_aq_r <- mkPulseWireOR(); // we may clear from different rules, the PulseWire allows for conflict-free scheduling
PulseWire set_aq_r <- mkPulseWireOR(); // pull setting into own rule such that defining set and clear as conflict-free becomes simple
// if the store queue is full, we cannot store; atomics may only be executed if it is empty
Wire#(Bool) store_queue_empty_w <- mkBypassWire();
Wire#(Bool) store_queue_full_w <- mkBypassWire();

// implement setting/clearing aq
// we do not deal with release separately since our implementation waits for an empty store buffer on an atomic anyways
// This may change if we get a sophisticated caching system ;)
rule clear_aq if (clear_aq_r);
    aq_r <= False;
endrule
(* mutually_exclusive = "clear_aq, set_aq" *)
rule set_aq if (set_aq_r);
    aq_r <= False;
endrule

// helper function to check if an address is misaligned. If it is, an exception is generated
function Bool check_misalign(Bit#(2) mask, Width width) = case (width)
    BYTE: False;
    HALF: (mask[0] != 0);
    WORD: (mask != 0);
endcase;

// helper function to translate instruction type to shorter representation of AMO types
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

// helper function to check whether reads may be speculatively executed ; this is usually OK in DMEM but not in IO space
function Bool is_speculative_region(UInt#(32) addr) = decodeAddressRange(addr, fromInteger(valueOf(BASE_DMEM)), fromInteger(valueOf(BASE_DMEM)+valueOf(SIZE_DMEM)));

// STORE HANDLING

`ifdef DEXIE
    RWire#(DexieMem) dexie_memw_local <- mkRWire();
    Wire#(Bool) dexie_stall_w <- mkBypassWire();
    FIFO#(MemWr) dexie_write_byp <- mkBypassFIFO();
`endif

// single-cycle calculation of stores
// real write occurs in storebuffer after successful commit
rule calculate_store if (!store_queue_full_w && in.first().opc == STORE && !aq_r && (rob_head == in.first().tag || valueOf(ROBDEPTH) == 1) && in.first().epoch == epoch_r[in.first().thread_id]
    `ifdef DEXIE
        && !dexie_stall_w
    `endif
);
    let inst = in.first(); in.deq();

    // calculate final access address
    UInt#(XLEN) final_addr = unpack(inst.rs1.Operand + getImmS({inst.remaining_inst, ?}));
    // bus addresses select entire words, therefore remove lower two bits
    UInt#(XLEN) axi_addr = final_addr & 'hfffffffc;

    // word provided for storage
    let raw_data = inst.rs2.Operand;

    // move bytes and half-words to the correct position in the memory word
    Bit#(XLEN) wr_data = case (inst.funct)
        W: raw_data;
        H: pack(replicate(raw_data[15:0]));
        B: pack(replicate(raw_data[7:0]));
    endcase;

    // calculate store mask for strobing of a full word
    Bit#(TDiv#(XLEN, 8)) mask = case (inst.funct)
        W: 'b1111;
        H: (pack(final_addr)[1] == 0 ? 'b0011 : 'b1100);
        B: (1 << pack(final_addr)[1:0]);
    endcase;

    // translate width from generic instruction representation to a shorter one just representing widths, not functions of other instructions
    Width width = case (inst.funct)
        W: WORD;
        H: HALF;
        B: BYTE;
    endcase;

    dbg_print(Mem, $format("instruction:  ", fshow(inst)));
    
    // write a result to the result bus - it may make sense to merge this pipeline with the read one to avoid muxing of results
    let local_result = Result {result : ((check_misalign(truncate(pack(final_addr)), width)) ? tagged Except AMO_ST_MISALIGNED : tagged Result 0) , new_pc : tagged Invalid, tag : inst.tag 
        `ifdef RVFI 
            , mem_addr: final_addr
        `endif
        };
    if (inst.exception matches tagged Valid .e) local_result.result = tagged Except e;

    out.enq(local_result);

    if (!check_misalign(truncate(pack(final_addr)), width)) 
    `ifndef DEXIE
        out_wr.enq(MemWr {mem_addr : axi_addr, data : wr_data, store_mask : mask});
    `else
        dexie_write_byp.enq(MemWr {mem_addr : axi_addr, data : wr_data, store_mask : mask});
    `endif


    `ifdef DEXIE
        dexie_memw_local.wset(DexieMem {
            pc:         inst.pc,
            instruction:{inst.remaining_inst, pack(inst.opc)},
            mem_addr:   pack(final_addr),
            size:       width,
            data:       raw_data
        } );
    `endif
endrule

`ifdef DEXIE
    rule fwd_dexie_write if (!dexie_stall_w);
        let write = dexie_write_byp.first(); dexie_write_byp.deq();
        out_wr.enq(write);
    endrule
`endif

// if an incoming store instruction was wrongly spaculated, flush it!
rule calculate_store_flush if (in.first().opc == STORE && in.first().epoch != epoch_r[in.first().thread_id]);
    let inst = in.first(); in.deq();

    // produce dummy result
    Result local_result = ?;
    local_result.tag = inst.tag;
    out.enq(local_result);
endrule


// LOAD / AMO HANDLING

// request/response buffers to talk to memory bus
FIFO#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType)))) mem_rd_or_amo_request <- mkBypassFIFO();
FIFO#(Bit#(XLEN)) mem_rd_or_amo_response <- mkBypassFIFO();

// STAGE 1: calculate address and request forwarding of data from store buffer

// inter-clock buffers
Wire#(LoadPipe) stage1_internal <- mkWire();
Wire#(Bool) response_ROB <- mkWire();
Reg#(UInt#(XLEN)) request_sb <- mkRegU();
//output to next stage
FIFO#(LoadPipe) stage1 <- mkPipelineFIFO();
PulseWire retry_sb_rq <- mkPulseWire();

rule calc_addr_load if ( (in.first().opc == LOAD || in.first().opc == AMO) && in.first().epoch == epoch_r[in.first().thread_id] && !aq_r);

    // get instruction
    let inst = in.first(); in.deq();
    // calculate address to which the store is pending
    let imm = (inst.opc == AMO ? 0 : getImmI({inst.remaining_inst, ?}));
    UInt#(XLEN) final_addr = unpack(inst.rs1.Operand + imm);

    // calculate load mask
    Bit#(TDiv#(XLEN, 8)) mask = case (inst.funct)
        W: 'b1111;
        H, HU: (pack(final_addr)[1] == 0 ? 'b0011 : 'b1100);
        B, BU: (1 << pack(final_addr)[1:0]);
    endcase;

    // fill internal data structure for load pipeline
    stage1.enq(LoadPipe {
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
        aq: unpack(inst.remaining_inst[19]),
        rl: unpack(inst.remaining_inst[18]),
        mispredicted: False,
        thread_id: inst.thread_id
    });
    dbg_print(Mem, $format("instruction:  ", fshow(inst)));

    // request data fwd from store buffer
    // note that this is a register, so the store buffer is probed every cycle until stage2 decides that the result is acceptable
    request_sb <= unpack({pack(inst.opc == AMO ? unpack(inst.rs1.Operand) : final_addr)[31:2], 2'b00});
    // if AMO, set aq register if aq access is required
    if ((inst.opc == AMO) && unpack(inst.remaining_inst[19])) set_aq_r.send();
endrule

// toss instructions with wrong epoch
rule flush_invalid_loads if ((in.first().opc == LOAD || in.first().opc == AMO) && in.first().epoch != epoch_r[in.first().thread_id]);
    let inst = in.first(); in.deq();
    stage1.enq(LoadPipe { tag: inst.tag, mispredicted: True});
endrule

// STAGE 2: forward data from store buffer

// intra-clock buffer to gather store buffer response
Wire#(Maybe#(MaskedWord)) response_sb <- mkWire();
// output to next stage
FIFO#(Tuple2#(LoadPipe, Maybe#(MaskedWord))) stage2 <- mkPipelineFIFO();

rule check_fwd_path_resp  if (stage1.first().epoch == epoch_r[stage1.first().thread_id] && !stage1.first().mispredicted);
    let struct_internal = stage1.first(); // get data from previous stage
    let response = response_sb; // get response from store buffer


    // if we are a simple read and the response matches our load/store mask or is invalid, move into next stage
    // otherwise wait
    if (!struct_internal.amo && (!isValid(response) || (response.Valid.store_mask & struct_internal.load_mask) == struct_internal.load_mask)) begin
        stage2.enq(tuple2(struct_internal, response));
        stage1.deq();
        dbg_print(Mem, $format("store buffer:  ", fshow(struct_internal), " ", fshow(response)));
    end
    // for AMOs, no forwarding is acceptable; if the SB response is valid, wait until previous writes are visible to other HARTs
    else if (struct_internal.amo && !isValid(response)) begin
        stage2.enq(tuple2(struct_internal, response));
        stage1.deq();
        dbg_print(AMO, $format("store buffer passed:  ", fshow(struct_internal)));
    end else begin
        dbg_print(AMO, $format("store buffer retry:  ", fshow(struct_internal), fshow(response)));
    end
endrule

// remove wrong-epoch instructions from pipeline
rule flush_invalid_fwds if (stage1.first().epoch != epoch_r[stage1.first().thread_id] || stage1.first().mispredicted);
    let internal_struct = stage1.first(); stage1.deq();
    if(internal_struct.aq) clear_aq_r.send();
    internal_struct.mispredicted = True;
    stage2.enq(tuple2(internal_struct, ?));
endrule


// STAGE 3: request via memory bus if required

// output to next stage
FIFO#(LoadPipe) stage3 <- mkPipelineFIFO();

rule request_axi_if_needed if (tpl_1(stage2.first()).epoch == epoch_r[tpl_1(stage2.first()).thread_id] && !tpl_1(stage2.first()).mispredicted);
    let struct_internal = tpl_1(stage2.first());
    let fwd = tpl_2(stage2.first());

    // no AMO instruction:
    if(!struct_internal.amo) begin
        // use fwd path if a value was found
        if(fwd matches tagged Valid .mw &&& is_speculative_region(struct_internal.addr)) begin
            stage2.deq();
            struct_internal.result = tagged Result mw.data;
            stage3.enq(struct_internal);
        end else
        // ask AXI if no value was found during forwarding from store buffer
        if(fwd matches tagged Invalid &&&
            (rob_head == struct_internal.tag || valueOf(ROBDEPTH) == 1 || is_speculative_region(struct_internal.addr))  // wait until we are sure read is correct-path or is in specualtive region
        ) begin
            // send request
            stage2.deq();
            stage3.enq(struct_internal);
            let addr = struct_internal.addr & 'hfffffffc;
            mem_rd_or_amo_request.enq(tuple2(pack(addr), tagged Invalid));
        end
    end
    else if( // if access is an AMO
            (rob_head == struct_internal.tag || valueOf(ROBDEPTH) == 1) && // wait until we are sure AMO is correct-path
            (struct_internal.rl ? store_queue_empty_w : True) // on a release, stall the AMO such that no writes are left pending
            ) begin
                // send AMO request
                dbg_print(AMO, $format("request:  ", fshow(struct_internal)));
                stage2.deq();
                stage3.enq(struct_internal);
                mem_rd_or_amo_request.enq(tuple2(pack(struct_internal.addr), tagged Valid tuple2(struct_internal.amo_modifier, struct_internal.amo_t)));
            end
endrule

// remove wrong-epoch instructions
rule flush_invalid_axi_rq if (tpl_1(stage2.first()).epoch != epoch_r[tpl_1(stage2.first()).thread_id] || tpl_1(stage2.first()).mispredicted);
    let internal_struct = tpl_1(stage2.first()); stage2.deq();
    if(internal_struct.aq) clear_aq_r.send();
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

// collect result from forwarding via SB
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

// collect result from memory bus
rule collect_result_read if(stage3.first().result matches tagged None &&& !stage3.first().mispredicted);
    stage3.deq();
    mem_rd_or_amo_response.deq();
    let resp = pack(mem_rd_or_amo_response.first());
    let internal_struct = stage3.first();

    // if the instruction was an atomic, clear aq register such that future instructions may be executed
    if(internal_struct.aq && internal_struct.amo) clear_aq_r.send();

    let result = internal_struct_and_data_to_result(internal_struct, resp);

    if(stage3.first().amo) dbg_print(AMO, $format("response:  ", fshow(internal_struct), fshow(resp)));

    // create misalign exception
    if(check_misalign(truncate(pack(internal_struct.addr)), internal_struct.width)) begin
        result.result = tagged Except (stage3.first().amo ? AMO_ST_MISALIGNED : MISALIGNED_LOAD);
    end

    dbg_print(Mem, $format("read (axi):  ", fshow(result)));

    `ifdef RVFI
        result.mem_addr = internal_struct.addr;
    `endif

    out.enq(result);
endrule

// flush mispredicted accesses
rule collect_result_mispredict if(stage3.first().mispredicted);
    stage3.deq();
    let internal_struct = stage3.first();
    if(internal_struct.aq) clear_aq_r.send();

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
(* preempts="calculate_store_flush, (collect_result_mispredict, collect_result_read, collect_result_read_bypass)" *)

// generate output
// output is wrapped as maybe, such that the result method is always active
rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);
endrule

// Functional Unit interface to receive instructions and broadcast results
interface FunctionalUnitIFC fu;
    method Action put(InstructionIssue inst);
        dbg_print(Mem, $format("got from RS:  ", fshow(inst)));
        in.enq(inst);
    endmethod
    method Maybe#(Result) get() = out_valid.wget();
endinterface

// request forwarding from store buffer
// the store buffer holds values to-be-written while the bus is occupied
// instead of waiting for write completion, we can read from here (if we are not in periphery-space)
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

// request interface to DMEM space
// IDMemAdapter separates requests between DMEM and periphery
interface Client request;
    interface Get request = toGet(mem_rd_or_amo_request);
    interface Put response = toPut(mem_rd_or_amo_response);
endinterface

// epoch handling
// increment local epoch upon flush
method Action flush(Vector#(NUM_THREADS, Bool) flags);
    for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
        if(flags[i]) epoch_r[i] <= epoch_r[i] + 1;
endmethod

// get current head pointer from the ROB
method Action current_rob_id(UInt#(rob_idx_t) idx) = rob_head._write(idx);

// feedback signals from store queue
method Action store_queue_empty(Bool b) = store_queue_empty_w._write(b);
method Action store_queue_full(Bool b) = store_queue_full_w._write(b);

interface Get write = toGet(out_wr);

`ifdef DEXIE
    method Maybe#(DexieMem) dexie_memw = dexie_memw_local.wget();
    method Action dexie_stall(Bool stall) = dexie_stall_w._write(stall);
`endif

endmodule


endpackage
