package Config;

typedef 4 IFUINST;
typedef 4 ISSUEWIDTH;

typedef 0 RESETVEC;

typedef 'h10000 BASE_DMEM;
typedef 'h10000 SIZE_DMEM;
typedef 'h00000 BASE_IMEM;
typedef 'h10000 SIZE_IMEM;

// must be at least as big as the issuewidth
typedef 4 ROB_BANK_DEPTH;

//must be at least as big as IFUINST and issuewidth
//and larger than 1 (required for MIMO)
typedef 16 INST_WINDOW;

// 0: single cycle
// 1: multi cycle
// 2: pipelined
typedef 2 MUL_DIV_STRATEGY;

// CSR and Mem units are always one
typedef 3 NUM_ALU;
typedef 1 NUM_MULDIV;
typedef 1 NUM_BR;

// Regfile as Latches
typedef 0 REGFILE_LATCH_BASED;
typedef 0 REGEVO_LATCH_BASED;
typedef 0 REGCSR_LATCH_BASED;

// rs depths
typedef 6 RS_DEPTH_ALU;
typedef 6 RS_DEPTH_MEM;
typedef 6 RS_DEPTH_CSR;
typedef 6 RS_DEPTH_MULDIV;
typedef 6 RS_DEPTH_BR;

// bus buffering
typedef 1 DECODE_LATCH_OUTPUT;
typedef 1 ROB_LATCH_OUTPUT;
typedef 1 RESBUS_ADDED_DELAY;

// add more stages
typedef 1 RS_LATCH_INPUT;
typedef 1 SPLIT_ISSUE_STAGE;

// prediction strategy
// 0: always untaken
// 1: smiths
typedef 3 BRANCHPRED;

typedef 6 BITS_BTB;
typedef 6 BITS_PHT;

typedef 6 BITS_BHR;

typedef 1  USE_RAS;
typedef 1 RAS_SAVE_HEAD;
typedef 1 RAS_SAVE_FIRST;
typedef 16 RASDEPTH;

typedef 8 STORE_BUF_DEPTH;

typedef 1 NUM_CPU;
typedef 1 NUM_THREADS;
endpackage
