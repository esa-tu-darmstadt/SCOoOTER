package SoC_Types;

// struct for access width
typedef enum {
        BYTE,
        HALF,
        WORD
} Width deriving(Bits, Eq, FShow);

endpackage