package Inst_Types;

import Types :: *;

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
    INVALID, NONE // Internally used if decode error resp. no function needed
} OpFunction deriving(Bits, Eq, FShow);

// Exception enum (maybe move to maybe here?)
typedef enum {
    ALU,
    LS,
    MULDIV,
    BR
} ExecUnitTag deriving(Bits, Eq, FShow);

typedef enum {
    NONE,
    INVALID_INST
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

// Struct containing all possible fields
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

} InstructionPredecode deriving(Bits, Eq, FShow);

typedef union tagged {
    RADDR Raddr;
    UInt#(TLog#(ROBDEPTH)) Tag;
    Bit#(XLEN) Operand;
} Operand deriving(Bits, Eq, FShow);

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
    Destination rd;

    //tag field for ROB
    UInt#(TLog#(ROBDEPTH)) tag;

    //immediate fields
    Bit#(XLEN) imm;

    Maybe#(ExceptionType) exception;

} Instruction deriving(Bits, Eq, FShow);

typedef struct {
    UInt#(TLog#(ROBDEPTH)) tag;
    union tagged {
        Bit#(XLEN) Result;
        ExceptionType Except;
    } result;
} Result deriving(Bits, FShow);

typedef struct {
    Bit#(XLEN) pc;
    RADDR destination;
    union tagged {
        UInt#(TLog#(ROBDEPTH)) Tag;
        Bit#(XLEN) Result;
        ExceptionType Except;
    } result;
} RobEntry deriving(Bits, FShow);

typedef struct {
    RADDR addr;
    Bit#(XLEN) data;
} RegWrite deriving(Bits, FShow);

typedef struct {
    RADDR addr;
    UInt#(TLog#(ROBDEPTH)) tag;
} RegReservation deriving(Bits, FShow);

typedef union tagged {
    UInt#(TLog#(ROBDEPTH)) Tag;
    Bit#(XLEN) Value;
} EvoResponse deriving(Bits, FShow);

endpackage