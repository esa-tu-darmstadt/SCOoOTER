package Inst_Types;

/*
  This package holds all combined types (e.g. structs and enums)
  which are used in multiple modules.
*/

import Types::*;
import Vector::*;

// Type definitions for instructions

// Function field names (encoding changes with opcode, see decode)
typedef enum {
    BEQ, BNE, BLT, BGE, BLTU, BGEU, // BRANCH
    B, H, W, // LOAD/STORE
    BU, HU, // LOAD
    ADD, SLT, SLTU, XOR, OR, AND, SLL, SRL, SRA, //OP/OPIMM/ATOMIC
    SUB, // OP
    FENCE, // MISCMEM
    ECALL, EBREAK, // SYSTEM
    MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU, //MULDIV
    LR, SC, SWAP, MIN, MAX, MINU, MAXU, //ATOMIC
    INVALID, NONE, // Internally used if decode error resp. no function needed
    RW, RS, RC, RWI, RSI, RCI, RET
} OpFunction deriving(Bits, Eq, FShow);

// Exception enum (maybe move to maybe here?)
typedef enum {
    ALU,
    LS,
    MULDIV,
    BR,
    CSR
} ExecUnitTag deriving(Bits, Eq, FShow);

// Type of an atomic memory operation
typedef enum {
    ADD,
    SWAP,
    AND,
    OR,
    XOR,
    MAX,
    MIN,
    MAXU,
    MINU,
    LR,
    SC,
    FENCE
} AmoType deriving(Bits, Eq, FShow);

// enum to convert a name to an exception number
typedef enum {
    MISALIGNED_ADDR = 0,
    INST_ACCESS_FAULT = 1,
    INVALID_INST = 2,
    BREAKPOINT = 3,
    MISALIGNED_LOAD = 4,
    LOAD_ACCESS_FAULT = 5,
    AMO_ST_MISALIGNED = 6,
    AMO_ST_ACCESS_FAULT = 7,
    ECALL_U = 8,
    ECALL_S = 9,
    ECALL_M = 11,
    INST_PAGE_FAULT = 12,
    LOAD_PAGE_FAULT = 13,
    AMO_ST_PAGE_FAULT = 15,
    NONE
} ExceptionType deriving(Bits, Eq, FShow);

// known Opcode values
typedef enum {
    LOAD = 7'b0000011,
    STORE = 7'b0100011,
    MADD = 7'b1000011,
    BRANCH = 7'b1100011,

    LOADFP = 7'b0000111,
    STOREFP = 7'b0100111,
    MSUB = 7'b1000111,
    JALR = 7'b1100111,

    CUSTOM0 = 7'b0001011,
    CUSTOM1 = 7'b0101011,
    NMSUB = 7'b1001011,
    RES0 = 7'b1101011,

    MISCMEM = 7'b0001111,
    AMO = 7'b0101111,
    NMADD = 7'b1001111,
    JAL = 7'b1101111,

    OPIMM = 7'b0010011,
    OP = 7'b0110011,
    OPFP = 7'b1010011,
    SYSTEM = 7'b1110011,

    AUIPC = 7'b0010111,
    LUI = 7'b0110111,
    RES1 = 7'b1010111,
    RES2 = 7'b1110111,
    
    OPIMM32 = 7'b0011011,
    OP32 = 7'b0111011,
    CUSTOM2 = 7'b1011011,
    CUSTOM3 = 7'b1111011

} OpCode deriving(Bits, Eq, FShow);

// Struct containing all possible fields of an instruction
typedef struct {
    Bit#(XLEN) pc;
    OpCode opc;

    //function fields
    Bit#(7) funct7;
    Bit#(3) funct3;

    //reg fields
    RADDR rs2;
    RADDR rs1;
    RADDR rd;

    //immediate fields
    Bit#(XLEN) immI;
    Bit#(XLEN) immS;
    Bit#(XLEN) immB;
    Bit#(XLEN) immU;
    Bit#(XLEN) immJ;

    UInt#(EPOCH_WIDTH) epoch;

    Bit#(XLEN) predicted_pc;

    Bit#(BITS_BHR) history;

    Bit#(RAS_EXTRA) ras;

} InstructionPredecode deriving(Bits, Eq, FShow);

// operand of an instruction
// can be a tag that has to still be produced
// or a value
// or a register address prior to gathering operands
typedef union tagged {
    RADDR Raddr;
    UInt#(TLog#(ROBDEPTH)) Tag;
    Bit#(XLEN) Operand;
} Operand deriving(Bits, Eq, FShow);

// destination of a result
// can be a register, memory or nothing
typedef union tagged {
    RADDR Raddr;
    Bit#(XLEN) MemAddr;
    void None;
} Destination deriving(Bits, Eq, FShow);

// struct containing condensed amount of fields
typedef struct {
    ExecUnitTag eut;
    Bit#(XLEN) pc;
    OpCode opc;

    //function fields for R type inst
    OpFunction funct;

    //atomic fields
    Bool aq;
    Bool rl;

    //reg fields
    Operand rs2;
    Operand rs1;
    RADDR rd;

    //tag field for ROB
    UInt#(TLog#(ROBDEPTH)) tag;

    //immediate fields
    Bit#(XLEN) imm;

    // track an occurred exception
    Maybe#(ExceptionType) exception;

    // epoch is used to synchronize all units in case of misprediction
    UInt#(EPOCH_WIDTH) epoch;

    // log predicted successor instruction
    Bit#(XLEN) predicted_pc;

    // save history for predictors
    Bit#(BITS_BHR) history;
    Bit#(RAS_EXTRA) ras;
} Instruction deriving(Bits, Eq, FShow);

// write accesses to memory
typedef struct {
    UInt#(XLEN) mem_addr;
    Bit#(XLEN) data;
    Bit#(TDiv#(XLEN, 8)) store_mask;
} MemWr deriving(Bits, FShow);

// word with a bytewise mask
typedef struct {
    Bit#(XLEN) data;
    Bit#(TDiv#(XLEN, 8)) store_mask;
} MaskedWord deriving(Bits, FShow);

// type tramsported via result bus
typedef struct {
    UInt#(TLog#(ROBDEPTH)) tag; // identifies producer instruction
    Maybe#(Bit#(XLEN)) new_pc; // if the control flow was redirected
    union tagged { // resulting value or exception
        Bit#(XLEN) Result;
        ExceptionType Except;
    } result;
    union tagged { // writes to mem or csr
        MemWr Mem;
        void None;
        CsrWrite Csr;
    } write;
} Result deriving(Bits, FShow);

// entries to reorder buffer
typedef struct {
    Bit#(XLEN) pc; // addr of the instruction
    RADDR destination; // destination register
    union tagged { // result (or tag identifying producing instruction)
        UInt#(TLog#(ROBDEPTH)) Tag;
        Bit#(XLEN) Result;
        ExceptionType Except;
    } result;
    // next real pc and predicted one
    Bit#(XLEN) next_pc;
    Bit#(XLEN) pred_pc;
    UInt#(EPOCH_WIDTH) epoch; // epoch to synchronize on misprediction
    union tagged { // writes to memory or CSRs
        MemWr Mem;
        void Pending_mem;
        void None;
        CsrWrite Csr;
    } write;
    // identify if the instruction is branching and if it is br or jal
    Bool branch;
    Bool br;
    // history for predictors
    Bit#(BITS_BHR) history;
    Bit#(RAS_EXTRA) ras;
    Bool ret; // instruction is branch return
} RobEntry deriving(Bits, FShow);

// write to a register
typedef struct {
    RADDR addr;
    Bit#(XLEN) data;
} RegWrite deriving(Bits, FShow);

// write to a csr
typedef struct {
    Bit#(12) addr;
    Bit#(XLEN) data;
} CsrWrite deriving(Bits, FShow);

// reserve tags for a register
typedef struct {
    RADDR addr;
    UInt#(TLog#(ROBDEPTH)) tag;
    UInt#(EPOCH_WIDTH) epoch;
} RegReservation deriving(Bits, FShow);
typedef struct {
    Vector#(ISSUEWIDTH, RegReservation) reservations;
    UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) count;
} RegReservations deriving(Bits, FShow);

// read response from evo regfile
typedef union tagged {
    UInt#(TLog#(ROBDEPTH)) Tag; // value still in flight
    Bit#(XLEN) Value; // value already produced
    void None; // no speculative result available, ask arch regs
} EvoResponse deriving(Bits, FShow);

// instruction right after fetch with metadata
typedef struct {
    Bit#(32) instruction;
    Bit#(32) pc;
    UInt#(EPOCH_WIDTH) epoch;
    // predictor metadata
    Bit#(32) next_pc;
    Bit#(BITS_BHR) history;
    Bit#(RAS_EXTRA) ras;
} FetchedInstruction deriving(Bits, FShow);

// output from fetch stage
typedef struct {
    UInt#(TLog#(TAdd#(IFUINST,1))) count;
    Vector#(IFUINST, FetchedInstruction) instructions;
} FetchResponse deriving(Bits, FShow);

// output from decode stage
typedef struct {
    UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) count;
    Vector#(ISSUEWIDTH, Instruction) instructions;
} DecodeResponse deriving(Bits, FShow);

// training info for predictors
typedef struct {
    Bit#(XLEN) pc; // pc of branching inst
    Bool taken; // was inst taken or untaken?
    Bit#(XLEN) target; // what is the branch target
    Bit#(BITS_BHR) history; // history from BHR
    Bool miss; // was the predictor wrong?
    Bool branch; // was this a br or jal?
} TrainPrediction deriving(Bits, FShow);

// direction predictor response
typedef struct{
    Bool pred;
    Bit#(BITS_BHR) history;
} Prediction deriving(Bits, FShow);

endpackage