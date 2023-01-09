package Debug;

import List::*;
import BuildList::*;
import BlueLibTests :: *;

// Tags used for debug prints
typedef enum {
    Decode,
    Issue,
    ROB,
    RS,
    Top,
    Fetch,
    ALU,
    Commit,
    Regs,
    BRU
} DbgTag deriving(Eq, FShow);

// List of currently allowed prints
List#(DbgTag) current_tags = list(Commit, ALU, Regs);

//  Function for printing text with a yellow label
function Action dbg_print(DbgTag tag, Fmt text);
    action
        if(elem(tag, current_tags))
            $display($format("%c[33m",27), "[", fshow(tag), "]: ", $format("%c[0m",27), text);
    endaction
endfunction

//  Function for printing error text with a red label
function Action err_print(DbgTag tag, Fmt text);
    action
            $display($format("%c[31m",27), "[", fshow(tag), "]: ", $format("%c[0m",27), text);
    endaction
endfunction

endpackage