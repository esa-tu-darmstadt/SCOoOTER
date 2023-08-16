package Decode;

import Inst_Types::*;
import Types::*;
import Interfaces::*;
import MIMO::*;
import Vector::*;
import GetPut::*;
import GetPutCustom::*;
import ESAMIMO::*;
import Config::*;

///////////////////////////////////////////////////
// This package implements decoding of instructions
//
// The package consists of the following parts:
// - Functions to extract specific fields from the inst
// - A predecode function that returns a struct with all possible fields
// - Functions to select and interpret the required fields per opcode
// - A decode function that returns a fully decoded inst
// - An implementation of a module capable of decoding instructions

//**********************************************
// Functions to extract fields from instructions

function OpCode getOpc(Bit#(ILEN) inst);
    OpCode opc = unpack(inst[6:0]);
    return opc;
endfunction

function Bit#(7) getFunct7(Bit#(ILEN) inst);
    return inst[31:25];
endfunction

function Bit#(3) getFunct3(Bit#(ILEN) inst);
    return inst[14:12];
endfunction

function RADDR getRs1(Bit#(ILEN) inst);
    return inst[19:15];
endfunction

function RADDR getRs2(Bit#(ILEN) inst);
    return inst[24:20];
endfunction

function RADDR getRd(Bit#(ILEN) inst);
    return inst[11:7];
endfunction

function Bit#(XLEN) getImmI(Bit#(ILEN) inst);
    return signExtend(inst[31:20]);
endfunction

function Bit#(XLEN) getImmS(Bit#(ILEN) inst);
    return signExtend( {inst[31:25],inst[11:7]} );
endfunction

function Bit#(XLEN) getImmB(Bit#(ILEN) inst);
    return signExtend( {inst[31],inst[7],inst[30:25],inst[11:8],1'b0} );
endfunction

function Bit#(XLEN) getImmU(Bit#(ILEN) inst);
    return{inst[31:12],0};
endfunction

function Bit#(XLEN) getImmJ(Bit#(ILEN) inst);
    return signExtend( {inst[31],inst[19:12],inst[20],inst[30:21],1'b0} );
endfunction


//**************************************************************
// Separates instruction word into struct of all possible fields
function InstructionPredecode predecode(Bit#(ILEN) inst, Bit#(XLEN) pc, UInt#(EPOCH_WIDTH) epoch, Bit#(XLEN) predicted_pc, Bit#(BITS_BHR) history, Bit#(RAS_EXTRA) ras, UInt#(TLog#(NUM_THREADS)) thread_id);
    return InstructionPredecode{
        pc : pc,
        opc : getOpc(inst),

        funct7 : getFunct7(inst),
        funct3 : getFunct3(inst),

        rs1 : getRs1(inst),
        rs2 : getRs2(inst),
        rd : getRd(inst),

        immI : getImmI(inst),
        immS : getImmS(inst),
        immB : getImmB(inst),
        immU : getImmU(inst),
        immJ : getImmJ(inst),

        epoch : epoch,

        predicted_pc : predicted_pc,
        history : history,

        ras: ras,

        thread_id: thread_id
    };

endfunction

//***************************************************
// Functions to select correct fields based on opcode

function Action print_inst(t inst) provisos(
    FShow#(t)
);
    return (action
        $display(fshow(inst));
    endaction);
endfunction

function Bit#(XLEN) select_imm(InstructionPredecode inst);
    return case(inst.opc)
        //SYSTEM uses U type as we must know which register is src
        LUI, AUIPC, SYSTEM                 : inst.immU;
        JAL                                : inst.immJ;
        JALR, LOAD, OPIMM, MISCMEM         : inst.immI;
        STORE                              : inst.immS;
        BRANCH                             : inst.immB;

        default : ?;
    endcase;
endfunction

function Operand select_rs1(InstructionPredecode inst);
    return case(inst.opc)
        BRANCH, LOAD, STORE, OPIMM, OP, MISCMEM, JALR, AMO, SYSTEM : tagged Raddr inst.rs1;
        default : tagged Operand 0;
    endcase;
endfunction

function Operand select_rs2(InstructionPredecode inst);
    return case(inst.opc)
        OP, BRANCH, STORE, AMO : tagged Raddr inst.rs2;
        default : tagged Operand 0;
    endcase;
endfunction

function RADDR select_rd(InstructionPredecode inst);
    return case(inst.opc)
        LUI, AUIPC, JAL, JALR, LOAD, OPIMM, OP, MISCMEM, AMO, SYSTEM : inst.rd;
        default : 0;
    endcase;
endfunction

function ExecUnitTag get_exec_unit(InstructionPredecode inst);
    return case(inst.opc)
        LOAD, STORE, AMO: LS;
        LUI, AUIPC, OPIMM: ALU;
        OP: case(inst.funct7)
            7'b0000001: MULDIV;
            default: ALU;
            endcase
        JAL, JALR, BRANCH: BR;
        SYSTEM: CSR;
        default: ALU;
    endcase;
endfunction

// Extract function from instruction if necessary
// Also detect if a function is invalid
function OpFunction getFunct(InstructionPredecode inst);
    return case(inst.opc)
        LUI: NONE;
        AUIPC: NONE;
        JAL: NONE;
        JALR: (inst.funct3 == 0 ? NONE : INVALID);
        BRANCH : case(inst.funct3)
            'b000: BEQ;
            'b001: BNE;
            'b100: BLT;
            'b101: BGE;
            'b110: BLTU;
            'b111: BGEU;
            default: INVALID;
            endcase
        LOAD : case(inst.funct3)
            'b000: B;
            'b001: H;
            'b010: W;
            'b100: BU;
            'b101: HU;
            default: INVALID;
            endcase
        STORE : case(inst.funct3)
            'b000: B;
            'b001: H;
            'b010: W;
            default: INVALID;
            endcase
        OPIMM : case(inst.funct3)
            'b000: ADD;
            'b010: SLT;
            'b011: SLTU;
            'b100: XOR;
            'b110: OR;
            'b111: AND;
            'b001: case(inst.funct7)
                'b0000000: SLL;
                default: INVALID;
                endcase
            'b101: case(inst.funct7)
                'b0000000: SRL;
                'b0100000: SRA;
                default: INVALID;
                endcase
            default: INVALID;
            endcase
        OP : case(inst.funct7)
                'b0000000 : case(inst.funct3)
                    'b000: ADD;
                    'b010: SLT;
                    'b011: SLTU;
                    'b100: XOR;
                    'b110: OR;
                    'b111: AND;
                    'b001: SLL;
                    'b101: SRL;
                    default: INVALID;
                    endcase
                'b0100000 : case(inst.funct3)
                    'b000 : SUB;
                    'b101 : SRA;
                    default: INVALID;
                    endcase
                'b0000001 : (valueOf(NUM_MULDIV) > 0 ? case(inst.funct3)
                    'b000 : MUL;
                    'b001 : MULH;
                    'b010 : MULHSU;
                    'b011 : MULHU;
                    'b100 : DIV;
                    'b101 : DIVU;
                    'b110 : REM;
                    'b111 : REMU;
                    default: INVALID;
                    endcase : INVALID);
                default: INVALID;
            endcase
        MISCMEM : case(inst.funct3)
            'b000: FENCE;
            default: INVALID;
            endcase
        SYSTEM : case(inst.funct3)
            'b000: case(inst.immI)
                0: ECALL;
                1: EBREAK;
                'b001100000010: RET;
                default: INVALID;
                endcase
            'b001: RW;
            'b010: RS;
            'b011: RC;
            'b101: RWI;
            'b110: RSI;
            'b111: RCI;
            default: INVALID;
            endcase
        AMO : case(inst.funct3)
            'b010 : case(inst.funct7[6:2])
                'b00010 : LR;
                'b00011 : SC;
                'b00001 : SWAP;
                'b00000 : ADD;
                'b00100 : XOR;
                'b01100 : AND;
                'b01000 : OR;
                'b10000 : MIN;
                'b10100 : MAX;
                'b11000 : MINU;
                'b11100 : MAXU;
                default : INVALID; 
                endcase
            default: INVALID;
            endcase

        default: INVALID;
    endcase;
endfunction

//*************************************************
// Create a instruction struct with required fields
function Instruction decode(InstructionPredecode inst);
    return Instruction {
        eut: get_exec_unit(inst),

        pc : inst.pc,
        //general opcode
        opc : inst.opc,

        //function fields for R-type instructions, garbage for other inst
        funct : getFunct(inst),

        //Atomic flags, only for A inst, garbage otherwise
        aq : unpack(inst.funct7[1]),
        rl : unpack(inst.funct7[0]),

        //registers, contains 0 if unused (or 0 is specified in inst)
        rs1 : select_rs1(inst),
        rs2 : select_rs2(inst),
        rd  : select_rd(inst),

        //set exception INVALID_INST if decode error
        exception : (getFunct(inst) == INVALID ? tagged Valid INVALID_INST : tagged Invalid),

        //immediate value, garbage if no immediate is used
        imm : select_imm(inst),

        tag : ?, //will be set in issue logic
        epoch : inst.epoch,

        predicted_pc : inst.predicted_pc,
        history : inst.history,

        ras: inst.ras,

        thread_id: inst.thread_id
    };
endfunction

function InstructionPredecode predecode_instruction_struct(FetchedInstruction in);
    return predecode(in.instruction, in.pc, in.epoch, in.next_pc, in.history, in.ras, in.thread_id);
endfunction

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkDecode(DecodeIFC) provisos (
        Bits#(Instruction, instruction_width_t),
        Log#(RASDEPTH, ras_log_t)
);

    `ifdef LOG_PIPELINE
        Reg#(UInt#(XLEN)) clk_ctr <- mkReg(0);
        rule count_clk; clk_ctr <= clk_ctr + 1; endrule
        Reg#(File) out_log <- mkRegU();
        rule open if (clk_ctr == 0);
            File out_log_l <- $fopen("scoooter.log", "a");
            out_log <= out_log_l;
        endrule
    `endif

    // select correct MIMO
    // the pipelined mimo schedules deq() prior to first() and enq() - therefore a circular dependency occurs if the output is not buffered
    // therefore the normal esamimo is used instead if no bufering is enabled, which schedules {first, enq} > deq
    MIMO#(IFUINST, ISSUEWIDTH, INST_WINDOW, Instruction) decoded_inst_m <- (valueOf(DECODE_LATCH_OUTPUT) == 1 ? mkESAMIMO_pipeline() : mkESAMIMO());
    PulseWire clear_buffer <- mkPulseWire();
    Reg#(DecodeResponse) buffer_output <- (valueOf(DECODE_LATCH_OUTPUT) == 1 ? mkReg(DecodeResponse {count: 0, instructions: ?}) : mkBypassWire());

    (* fire_when_enabled,no_implicit_conditions *)
    rule fill_buffer;
        let inst_vec = decoded_inst_m.first();
        MIMO::LUInt#(ISSUEWIDTH) amount_loc = truncate(min(decoded_inst_m.count(), fromInteger(valueOf(ISSUEWIDTH))));
        buffer_output <= DecodeResponse {count: amount_loc, instructions: inst_vec};
    endrule

    interface Put instructions;
        method Action put(FetchResponse inst_from_decode) if (decoded_inst_m.enqReadyN(fromInteger(valueOf(IFUINST))));
            if (!clear_buffer) begin
                let decoded_vec = Vector::map(compose(decode, predecode_instruction_struct), inst_from_decode.instructions);
                decoded_inst_m.enq(inst_from_decode.count, decoded_vec);
                `ifdef LOG_PIPELINE
                    for(Integer i = 0; i < valueOf(IFUINST); i=i+1) if(fromInteger(i) < inst_from_decode.count)
                        $fdisplay(out_log, "%d DECODE %x ", clk_ctr, decoded_vec[i].pc, fshow(decoded_vec[i].opc), " ", fshow(decoded_vec[i].funct), " ", fshow(decoded_vec[i].rd), " ", fshow(decoded_vec[i].rs1 matches tagged Raddr .r ? fshow(r) : decoded_vec[i].rs1 matches tagged Operand .r ? fshow("xx") : fshow("IM")), " ", fshow(decoded_vec[i].rs2 matches tagged Raddr .r ? fshow(r) : fshow("IM")), " ", decoded_vec[i].epoch);
                `endif
            end
        endmethod
    endinterface

    interface GetSC decoded_inst;
        method DecodeResponse first;
            return buffer_output;
        endmethod
        method Action deq(MIMO::LUInt#(ISSUEWIDTH) amount) = decoded_inst_m.deq(amount);
    endinterface

    method Action flush();
        decoded_inst_m.clear();
    endmethod  
    
endmodule

endpackage