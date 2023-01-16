package Config;

typedef 1 IFUINST;
typedef 1 ISSUEWIDTH;

typedef 0 RESETVEC;
typedef 'h10000 BRAMSIZE;

// must be at least as big as the issuewidth
typedef 1 ROBDEPTH;

//must be at least as big as IFUINST and issuewidth
//and larger than 1 (required for MIMO)
typedef 2 INST_WINDOW;

// 0: single cycle
// 1: multi cycle
// 2: pipelined
typedef 0 DIV_STRATEGY;

typedef 6 NUM_FU;
typedef 6 NUM_RS;

endpackage