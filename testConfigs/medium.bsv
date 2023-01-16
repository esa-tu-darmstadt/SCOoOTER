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
typedef 1 DIV_STRATEGY;

typedef 6 NUM_FU;
typedef 6 NUM_RS;

endpackage
