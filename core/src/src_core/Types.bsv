package Types;

// TODO: Clean up and use provisos
 
typedef 32 XLEN;
typedef 32 ILEN;
typedef Bit#(ILEN) INST;
typedef Bit#(XLEN) WORD;
typedef TMul#(XLEN, 4) IFUWIDTH;
typedef Bit#(IFUWIDTH) IFUWORD;
typedef 0 RESETVEC;
typedef 'h10000 BRAMSIZE;

typedef Bit#(5) RADDR;

endpackage