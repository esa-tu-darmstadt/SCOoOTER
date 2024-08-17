package Types;

/*

Simple numeric types

*/

import Config::*;
export Config::*;
export Types::*;

typedef 32 XLEN;
typedef 32 ILEN;
typedef 30 PCLEN;

typedef Bit#(5) RADDR;

typedef TAdd#(
            TMul#(RAS_SAVE_HEAD, TLog#(RASDEPTH)),
            TMul#(RAS_SAVE_FIRST, PCLEN)
            )
            RAS_EXTRA;

typedef TAdd#(
            TAdd#(
                TAdd#(NUM_ALU, NUM_MULDIV), NUM_BR),
            2
            )
            NUM_FU;

typedef NUM_FU NUM_RS;

typedef TLog#(TAdd#(TAdd#(IFUINST,ROBDEPTH),INST_WINDOW)) EPOCH_WIDTH;

typedef TMul#(NUM_CPU, NUM_THREADS) NUM_HARTS;

typedef TMul#(ISSUEWIDTH, ROB_BANK_DEPTH) ROBDEPTH;
endpackage