package Config;

typedef 2 IFUINST;
typedef 2 ISSUEWIDTH;

typedef 0 RESETVEC;
typedef 'h10000 BRAMSIZE;

// must be at least as big as the issuewidth
typedef 7 ROBDEPTH;

//must be at least as big as IFUINST and issuewidth
//and larger than 1 (required for MIMO)
typedef 16 INST_WINDOW;

// 0: single cycle
// 1: multi cycle
// 2: pipelined
typedef 1 MUL_DIV_STRATEGY;

// CSR and Mem units are always one
typedef 2 NUM_ALU;
typedef 1 NUM_MULDIV;
typedef 1 NUM_BR;

// rs depths
typedef 4 RS_DEPTH_ALU;
typedef 4 RS_DEPTH_MEM;
typedef 4 RS_DEPTH_CSR;
typedef 4 RS_DEPTH_MULDIV;
typedef 4 RS_DEPTH_BR;

// bus buffering
typedef 0 RS_LATCH_BUS;
typedef 1 DECODE_LATCH_OUTPUT;
typedef 1 ROB_LATCH_OUTPUT;
typedef 0 RESBUS_ADDED_DELAY;
typedef 0 RS_LATCH_INPUT;

// prediction strategy
// 0: always untaken
// 1: smiths
typedef 2 BRANCHPRED;

typedef 5 BITS_BTB;
typedef 5 BITS_PHT;

typedef 5 BITS_BHR;

typedef 1  USE_RAS;
typedef 1 RAS_SAVE_HEAD;
typedef 1 RAS_SAVE_FIRST;
typedef 16 RASDEPTH;

typedef 8 STORE_BUF_DEPTH;

typedef 1 NUM_CPU;
endpackage
