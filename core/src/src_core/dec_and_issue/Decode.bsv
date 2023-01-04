package Decode;

import Inst_Types :: *;
import Types :: *;

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
function InstructionPredecode predecode(Bit#(ILEN) inst, Bit#(XLEN) pc);
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
        immJ : getImmJ(inst)
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
        LUI, AUIPC                         : inst.immU;
        JAL                                : inst.immJ;
        JALR, LOAD, OPIMM, MISCMEM, SYSTEM : inst.immI;
        STORE                              : inst.immS;
        BRANCH                             : inst.immB;

        default : ?;
    endcase;
endfunction

function Operand select_rs1(InstructionPredecode inst);
    return case(inst.opc)
        BRANCH, LOAD, STORE, OPIMM, OP, MISCMEM : tagged Raddr inst.rs1;
        default : tagged Operand 0;
    endcase;
endfunction

function Operand select_rs2(InstructionPredecode inst);
    return case(inst.opc)
        OP, BRANCH, STORE, AMO : tagged Raddr inst.rs2;
        default : tagged Operand 0;
    endcase;
endfunction

function Destination select_rd(InstructionPredecode inst);
    return case(inst.opc)
        LUI, AUIPC, JAL, JALR, LOAD, OPIMM, OP, MISCMEM, AMO : tagged Raddr inst.rd;
        default : tagged None;
    endcase;
endfunction

function ExecUnitTag get_exec_unit(InstructionPredecode inst);
    return case(inst.opc)
        LOAD, STORE: LS;
        LUI, AUIPC, OPIMM: ALU;
        OP: case(inst.funct7)
            7'b0000001: MULDIV;
            default: ALU;
            endcase
        JAL, JALR, BRANCH: BR;
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
                'b0000001 : case(inst.funct3)
                    'b000 : MUL;
                    'b001 : MULH;
                    'b010 : MULHSU;
                    'b011 : MULHU;
                    'b100 : DIV;
                    'b110 : REM;
                    'b111 : REMU;
                    default: INVALID;
                    endcase
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
                default: INVALID;
                endcase
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
                'b11000 : MAX;
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
    return Instruction{
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
        imm : select_imm(inst)
    };
endfunction

module mkDecode(DecodeIFC);

endmodule

endpackage