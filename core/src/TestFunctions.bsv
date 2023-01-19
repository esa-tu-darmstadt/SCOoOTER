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

endpackage

