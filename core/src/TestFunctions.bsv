package TestFunctions;

import Types :: *;
import Inst_Types :: *;
import Vector::*;

function a disassemble_creg(Integer num, Array#(a) creg);
    return creg[num];
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

endpackage

