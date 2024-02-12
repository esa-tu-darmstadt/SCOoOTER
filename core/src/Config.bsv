package Config;

typedef 1 IFUINST;
typedef 1 ISSUEWIDTH;

typedef 0 RESETVEC;
typedef 'h20000 BRAMSIZE;

// must be at least as big as the issuewidth
typedef 2 ROBDEPTH;

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
typedef 2 RS_DEPTH_ALU;
typedef 2 RS_DEPTH_MEM;
typedef 2 RS_DEPTH_CSR;
typedef 2 RS_DEPTH_MULDIV;
typedef 2 RS_DEPTH_BR;

// bus buffering
typedef 0 RS_LATCH_BUS;
typedef 0 DECODE_LATCH_OUTPUT;
typedef 0 ROB_LATCH_OUTPUT;
typedef 0 RESBUS_ADDED_DELAY;
typedef 0 RS_LATCH_INPUT;

// prediction strategy
// 0: always untaken
// 1: smiths
typedef 1 BRANCHPRED;

typedef 5 BITS_BTB;
typedef 5 BITS_PHT;

typedef 0 BITS_BHR;

typedef 1  USE_RAS;
typedef 1 RAS_SAVE_HEAD;
typedef 1 RAS_SAVE_FIRST;
typedef 16 RASDEPTH;

typedef 8 STORE_BUF_DEPTH;

// features

typedef 1 NUM_CPU;
typedef 1 NUM_THREADS;
endpackage
