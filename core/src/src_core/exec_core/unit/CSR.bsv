package CSR;

/*
  This is the CSR FU

  unlike the arch regs, we do not use a
  speculative shadow regfile for CSRs as
  the regfile is quite large and CSR inst quite
  infrequent.

  We therefore have a signal from ROB that tells
  us if a CSR instruction may perform.
  I.e. the instruction will be executed if it is the next instruction
  to be committed, because we can be sure that it is not speculative any more.

  Interrupt returns (mret instructions) also pass through here as
  they share the system opcode.
*/

import Interfaces::*;
import Types::*;
import Inst_Types::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import RWire::*;
import Debug::*;
import GetPut::*;
import ClientServer::*;
import Vector::*;

// CSR operation enum
typedef enum {
        RW,
        RS,
        RC,
        RWI,
        RSI,
        RCI,
        RET,
        ECALL,
        EBREAK
} OpType deriving(Bits, Eq, FShow);

// internal struct used between stages
typedef struct {
    UInt#(TLog#(ROBDEPTH)) tag;
    OpType op;
    Bool except;
    Bit#(XLEN) operand;
    Bit#(12) addr;
    UInt#(EPOCH_WIDTH) epoch;
    UInt#(TLog#(NUM_THREADS)) thread_id;
    Bool is_readonly_inst;
} Internal_struct deriving(Bits, FShow);

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkCSR(CsrIFC) provisos (
    Log#(ROBDEPTH, rob_idx_t)
);

// local epoch for tossing wrong-path instructions
// this reduces bus pressure 
Vector#(NUM_THREADS, Reg#(UInt#(EPOCH_WIDTH))) epoch_r <- replicateM(mkReg(0));

// in, out FIFOS and output wire
FIFO#(InstructionIssue) in <- mkPipelineFIFO();
FIFOF#(Result) out <- mkFIFOF();
RWire#(Result) out_valid <- mkRWire();

// CSR operations should be kept atomic - stall until previous op is done
Reg#(Bool) inflight_r <- mkReg(False);

// outgoing csr write
FIFO#(CsrWrite) out_wr <- mkFIFO();

// ROB head ID - check if current instruction should be committed
Wire#(UInt#(rob_idx_t)) rob_head <- mkBypassWire();

// req and resp wires for CSR reading
FIFO#(CsrRead) csr_req <- mkBypassFIFO();
Wire#(Maybe#(Bit#(XLEN))) csr_res <- mkBypassWire();
// Buffer between stages
FIFO#(Internal_struct) stage1 <- mkFIFO();

// request CSR read and enqueue into buffer between stages
// wait for previous operation and make sure that current operation should be commited
rule get_request if ((!inflight_r) && (valueOf(ROBDEPTH) == 1 || in.first().tag == rob_head));
    let inst = in.first(); in.deq();

    // flag unit as busy
    inflight_r <= True;

    // generate address and immediate value
    Bit#(12) csr_addr = truncateLSB(inst.remaining_inst);
    Bit#(5) csr_imm = inst.remaining_inst[12:8];

    dbg_print(CSR, $format("%x", inst.pc));

    // request csr read
    if(inst.funct != RET &&
       inst.funct != ECALL &&
       inst.funct != EBREAK
       ) csr_req.enq(CsrRead {addr: csr_addr, thread_id: inst.thread_id});

    // build operand to be applied
    let op = case (inst.funct)
        RW,  RS,  RC:  inst.rs1.Operand;
        RWI, RSI, RCI: zeroExtend(csr_imm);
    endcase;

    // store data for next stage
    stage1.enq(Internal_struct {
        tag: inst.tag,
        except: isValid(inst.exception),
        op: case (inst.funct)
                RW:      RW;
                RS:      RS;
                RC:      RC;
                RWI:     RWI;
                RSI:     RSI;
                RCI:     RCI;
                RET:     RET;
                ECALL:   ECALL;
                EBREAK:  EBREAK;
            endcase,
        is_readonly_inst: (inst.remaining_inst[12:8] == 5'h0),
        operand: op,
        addr: csr_addr,
        epoch: inst.epoch,
        thread_id: inst.thread_id
    });
endrule

// read the CSR and write it if needed
rule read_modify (stage1.first().op != RET && stage1.first().op != ECALL && stage1.first().op != EBREAK);
    let csr_data = csr_res;
    let internal = stage1.first(); stage1.deq();
    
    dbg_print(CSR, $format("read: %x %x", internal.addr, csr_data));

    // variable to hold outgoing result
    Result res = unpack(0);

    // find out if the CSR is readonly, if the instruction matches the CSR type and whether the instruction is invalid
    Bool is_readonly_csr = 2'b11 == truncateLSB(internal.addr);
    Bool is_readonly_inst = (internal.is_readonly_inst) && (internal.op == RS || internal.op == RSI || internal.op == RC || internal.op == RCI);
    Bool is_invalid_inst = is_readonly_csr && !is_readonly_inst;

    // return read data and csr writing request
    if(csr_data matches tagged Valid .data) begin

        // modify data
        let out = case (internal.op)
            RW, RWI: internal.operand;
            RS, RSI: (data | internal.operand);
            RC, RCI: (data & ~internal.operand);
        endcase;

        // produce outgoing result for result bus
        res = Result {
            result : (is_invalid_inst ? tagged Except INVALID_INST : tagged Result data),
            new_pc : tagged Invalid,
            tag : internal.tag
        };
        if (!is_invalid_inst && stage1.first.epoch() == epoch_r[stage1.first().thread_id]) begin
            out_wr.enq(CsrWrite {addr: internal.addr, data: out, thread_id: internal.thread_id});
        end
    end else // if no read was returned, the CSR does not exist
        // non-existing CSR - dummy result
        res = Result {
            result : tagged Except INVALID_INST,
            new_pc : tagged Invalid,
            tag : internal.tag
        };

    out.enq(res);
endrule

// for an interrupt return, return dummy values
rule dummy_result_ret (stage1.first().op == RET || stage1.first().op == ECALL || stage1.first().op == EBREAK);
    let internal = stage1.first(); stage1.deq();
    let res = Result {
        result : (!internal.except ? case (stage1.first().op)
                                        RET:    tagged Result 0;
                                        ECALL:  tagged Except ECALL_M;
                                        EBREAK: tagged Except BREAKPOINT;
                                      endcase : tagged Except INVALID_INST),
        new_pc : tagged Invalid,
        tag : internal.tag
    };
    out.enq(res);
endrule

// propagate result to out wires
rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);
endrule

// make sure next operation can start
rule clear_inflight if (inflight_r && out.notEmpty());
    inflight_r <= False;
endrule

// FU interface
interface FunctionalUnitIFC fu;
    method Action put(InstructionIssue inst) = in.enq(inst);
    method Maybe#(Result) get() = out_valid.wget();
endinterface

// CSR read interface
interface Client csr_read;
    interface Get request = toGet(csr_req);
    interface Put response;
        method Action put(Maybe#(Bit#(XLEN)) in) = csr_res._write(in);
    endinterface
endinterface

// input from ROB
method Action current_rob_id(UInt#(rob_idx_t) idx) = rob_head._write(idx);

// epoch handling
method Action flush(Vector#(NUM_THREADS, Bool) flags);
    for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
        if(flags[i]) begin
            epoch_r[i] <= epoch_r[i] + 1;
        end
endmethod

interface Get write = toGet(out_wr);

endmodule


endpackage

