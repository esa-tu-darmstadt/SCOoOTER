package CSR;

import Interfaces::*;
import Types::*;
import Inst_Types::*;
import FIFO::*;
import SpecialFIFOs::*;
import RWire::*;
import Debug::*;
import GetPut::*;
import ClientServer::*;

typedef enum {
        RW,
        RS,
        RC,
        RWI,
        RSI,
        RCI,
        RET
} OpType deriving(Bits, Eq, FShow);

typedef struct {
    UInt#(TLog#(ROBDEPTH)) tag;
    OpType op;
    Bool except;
    Bit#(XLEN) operand;
    Bit#(12) addr;
} Internal_struct deriving(Bits, FShow);

(* synthesize *)
module mkCSR(CsrIFC);

FIFO#(Instruction) in <- mkPipelineFIFO();
FIFO#(Result) out <- mkPipelineFIFO();
RWire#(Result) out_valid <- mkRWire();

FIFO#(Bit#(12))   csr_req <- mkBypassFIFO();
FIFO#(Maybe#(Bit#(XLEN))) csr_res <- mkBypassFIFO();

FIFO#(Internal_struct) stage1 <- mkPipelineFIFO();

Wire#(Bool) blocked <- mkBypassWire();

rule get_request if (!blocked);
    let inst = in.first(); in.deq();

    Bit#(12) csr_addr = inst.imm[31:20];
    Bit#(5) csr_imm = inst.imm[19:15];

    // request
    if(inst.funct != RET) csr_req.enq(csr_addr);

    //operand
    let op = case (inst.funct)
        RW,  RS,  RC:  inst.rs1.Operand;
        RWI, RSI, RCI: zeroExtend(csr_imm);
    endcase;

    stage1.enq(Internal_struct {
        tag: inst.tag,
        except: isValid(inst.exception),
        op: case (inst.funct)
                RW: RW;
                RS: RS;
                RC: RC;
                RWI: RWI;
                RSI: RSI;
                RCI: RCI;
                RET: RET;
            endcase,
        operand: op,
        addr: csr_addr
    });
endrule

rule read_modify (stage1.first().op != RET);
    let csr_data = csr_res.first(); csr_res.deq();
    let internal = stage1.first(); stage1.deq();

    Result res = ?;

    if(csr_data matches tagged Valid .data) begin
        let out = case (internal.op)
            RW, RWI: internal.operand;
            RS, RSI: (data | internal.operand);
            RC, RCI: (data & ~internal.operand);
        endcase;

        res = Result {
            result : tagged Result data,
            new_pc : tagged Invalid,
            tag : internal.tag, 
            write : tagged Csr CsrWrite {addr: internal.addr, data: out}
        };
    end else
        res = Result {
            result : tagged Except INVALID_INST,
            new_pc : tagged Invalid,
            tag : internal.tag, 
            write : tagged None
        };

    out.enq(res);

endrule

rule dummy_result_ret (stage1.first().op == RET);
    let internal = stage1.first(); stage1.deq();
    let res = Result {
        result : tagged Result 0,
        new_pc : tagged Invalid,
        tag : internal.tag, 
        write : tagged None
    };

    out.enq(res);
endrule

rule propagate_result;
    out.deq();
    let res = out.first();
    out_valid.wset(res);
endrule

interface FunctionalUnitIFC fu;
    method Action put(Instruction inst);
        in.enq(inst);
    endmethod

    method Maybe#(Result) get() =
        out_valid.wget();
endinterface

interface Client csr_read;

    interface Get request = toGet(csr_req);
    interface Put response = toPut(csr_res);

endinterface

method Action block(Bool b);
    blocked <= b;
endmethod



endmodule


endpackage