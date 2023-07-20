package TestFunctions;

/*
  Functions for tests on vectors, structs and other types
*/

import Types :: *;
import Inst_Types :: *;
import Vector::*;

function a disassemble_creg(Integer num, Array#(a) creg);
    return creg[num];
endfunction

//TODO: use less sequential algorithm
function UInt#(a) find_nth(UInt#(a) num, b cmp, Vector#(c, b) vec) provisos(
    Eq#(b)
);
    UInt#(a) found = 0;
    UInt#(a) out = ?;
    for(Integer i = 0; i < valueOf(c); i = i + 1) begin
        if(vec[i] == cmp) begin
            found = found + 1;
            if(found == num) out = fromInteger(i);
        end
    end
    return out;
endfunction

function Maybe#(a) find_nth_valid(Integer num, Vector#(vsize, Maybe#(a)) data);
    Integer found = 0;
    Maybe#(a) res = tagged Invalid;
    for(Integer i = 0; i < valueOf(vsize); i=i+1) begin
        if(data[i] matches tagged Valid .v) begin
            if(found == num) res = data[i];
            found = found + 1;
        end
    end

    return res;
endfunction

function String select_fitting_prog_binary(Integer width);
    return case (width)
        1: "32";
        2: "64";
        3: "96";
        4: "128";
        5: "160";
        6: "192";
        7: "224";
        8: "256";
    endcase;
endfunction

function String select_fitting_sram_byte(Integer bnum);
    return case (bnum)
        0: "0";
        1: "1";
        2: "2";
        3: "3";
    endcase;
endfunction

// this helper function tests if an index is part of a ROB slice / circular buffer defined by a HEAD and TAIL pointer
function Bool part_of_rob_slice(Bool def, UInt#(TLog#(ROBDEPTH)) head, UInt#(TLog#(ROBDEPTH)) tail, UInt#(TLog#(ROBDEPTH)) test);
    Bool out;
    if(head > tail) begin
        out = head > test && test >= tail;
    end else if (head < tail) begin
        out = test >= tail || test < head;
    end else
        out = def;
    return out;
endfunction

function Bool ispwr2(Integer test);
    Maybe#(Bool) ret = tagged Invalid;
    while (!isValid(ret)) begin
        if (test == 1) ret = tagged Valid True;
        else if (test%2 != 0) ret = tagged Valid False;
        test = test/2;
    end
    return ret.Valid;
endfunction

endpackage

