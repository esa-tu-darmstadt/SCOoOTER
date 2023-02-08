package Types;

import Config::*;
export Config::*;
export Types::*;

typedef 32 XLEN;
typedef 32 ILEN;

typedef Bit#(5) RADDR;

typedef TAdd#(
            TMul#(RAS_SAVE_HEAD, TLog#(RASDEPTH)),
            TMul#(RAS_SAVE_FIRST, XLEN)
            )
            RAS_EXTRA;

endpackage