package Config;

typedef 3 IFUINST;
typedef 3 ISSUEWIDTH;

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

// CSR, Br and Mem units are always one
typedef 2 NUM_ALU;
typedef 1 NUM_MULDIV;

// rs depths
typedef 4 RS_DEPTH_ALU;
typedef 4 RS_DEPTH_MEM;
typedef 4 RS_DEPTH_CSR;
typedef 4 RS_DEPTH_MULDIV;
typedef 4 RS_DEPTH_BR;

// prediction strategy
// 0: always untaken
// 1: smiths
typedef 1 BRANCHPRED;

typedef 10 BITS_BTB;
typedef 10 BITS_PHT;

typedef 0 BITS_BHR;

typedef 1  USE_RAS;
typedef 1 RAS_SAVE_HEAD;
typedef 1 RAS_SAVE_FIRST;
typedef 16 RASDEPTH;

typedef 8 STORE_BUF_DEPTH;
endpackage
