package Config;

typedef 8 IFUINST;
typedef 4 ISSUEWIDTH;

typedef 0 RESETVEC;
typedef 'h10000 BRAMSIZE;

// must be at least as big as the issuewidth
typedef 16 ROBDEPTH;

//must be at least as big as IFUINST and issuewidth
//and larger than 1 (required for MIMO)
typedef 16 INST_WINDOW;

// 0: single cycle
// 1: multi cycle
// 2: pipelined
typedef 2 MUL_DIV_STRATEGY;

typedef 7 NUM_FU;
typedef 7 NUM_RS;


// prediction strategy
// 0: always untaken
// 1: smiths
typedef 2 BRANCHPRED;

typedef 8 BITS_BTB;
typedef 8 BITS_PHT;

typedef 8 BITS_BHR;

typedef 1  USE_RAS;
typedef 1 RAS_SAVE_HEAD;
typedef 1 RAS_SAVE_FIRST;
typedef 16 RASDEPTH;
endpackage
