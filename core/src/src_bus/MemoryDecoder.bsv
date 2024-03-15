package MemoryDecoder;

/*

Helper functions to check if a memory address is in a certain range

*/

// upper and lower bound
function Bool decodeAddressRange(t addr, t lower, t upper) provisos (
    Ord#(t)
);
    return (lower <= addr && addr < upper);
endfunction

// upper bound
function Bool decodeAddressIsLower(t addr, t upper) provisos (
    Ord#(t)
);
    return (addr < upper);
endfunction

// lower bound
function Bool decodeAddressIsHigher(t addr, t lower) provisos (
    Ord#(t)
);
    return (lower <= addr);
endfunction

endpackage