package MemoryDecoder;

function Bool decodeAddressRange(t addr, t lower, t upper) provisos (
    Ord#(t)
);
    return (lower <= addr && addr < upper);
endfunction

function Bool decodeAddressIsLower(t addr, t upper) provisos (
    Ord#(t)
);
    return (addr < upper);
endfunction

function Bool decodeAddressIsHigher(t addr, t lower) provisos (
    Ord#(t)
);
    return (lower <= addr);
endfunction

endpackage