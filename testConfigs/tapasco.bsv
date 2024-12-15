package Config;
// Config for TaPaSCo
typedef 1 IFUINST;
typedef 1 ISSUEWIDTH;

typedef 'h0 RESETVEC;

// Memory sizes, default matches default in tapasco-riscv, this should never be reached with the current makefile
`ifndef TAPASCO_BRAM_SIZE
`define TAPASCO_BRAM_SIZE 'h4000
`endif

typedef 'h0 BASE_IMEM;
typedef `TAPASCO_BRAM_SIZE SIZE_IMEM;
typedef `TAPASCO_BRAM_SIZE BASE_DMEM;
typedef `TAPASCO_BRAM_SIZE SIZE_DMEM;

// must be at least as big as the issuewidth
typedef 8 ROB_BANK_DEPTH;

//must be at least as big as IFUINST and issuewidth
//and larger than 1 (required for MIMO)
typedef 2 INST_WINDOW;

// 0: single cycle
// 1: multi cycle
// 2: pipelined
typedef 1 MUL_DIV_STRATEGY;

// CSR and Mem units are always one
typedef 1 NUM_ALU;
typedef 1 NUM_MULDIV;
typedef 1 NUM_BR;

// Regfile as Latches
typedef 0 REGFILE_LATCH_BASED;
typedef 0 REGEVO_LATCH_BASED;
typedef 0 REGCSR_LATCH_BASED;

// rs depths
typedef 1 RS_DEPTH_ALU;
typedef 1 RS_DEPTH_MEM;
typedef 1 RS_DEPTH_CSR;
typedef 1 RS_DEPTH_MULDIV;
typedef 1 RS_DEPTH_BR;

// bus buffering
typedef 0 RS_LATCH_BUS;
typedef 0 DECODE_LATCH_OUTPUT;
typedef 0 ROB_LATCH_OUTPUT;
typedef 0 RESBUS_ADDED_DELAY;

// add more stages
typedef 0 RS_LATCH_INPUT;
typedef 0 SPLIT_ISSUE_STAGE;

// prediction strategy
// 0: always untaken
// 1: smiths
typedef 0 BRANCHPRED;

typedef 5 BITS_BTB;
typedef 5 BITS_PHT;

typedef 0 BITS_BHR;

typedef 0  USE_RAS;
typedef 1 RAS_SAVE_HEAD;
typedef 0 RAS_SAVE_FIRST;
typedef 16 RASDEPTH;

typedef 4 STORE_BUF_DEPTH;

typedef 1 NUM_CPU;
typedef 1 NUM_THREADS;
endpackage : Config