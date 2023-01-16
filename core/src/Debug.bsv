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
    RegEvo,
    BRU,
    None
} DbgTag deriving(Eq, FShow);

// List of currently allowed prints
List#(DbgTag) current_tags = list(Commit);

//  Function for printing text with a yellow label
function Action dbg_print(DbgTag tag, Fmt text);
    action
        `ifdef CUSTOM_TB
            if(elem(tag, current_tags))
                $display($format("%c[33m",27), "[", fshow(tag), "]: ", $format("%c[0m",27), text);
        `endif
    endaction
endfunction

//  Function for printing error text with a red label
function Action err_print(DbgTag tag, Fmt text);
    action
            `ifdef CUSTOM_TB
                $display($format("%c[31m",27), "[", fshow(tag), "]: ", $format("%c[0m",27), text);
            `endif
    endaction
endfunction

endpackage