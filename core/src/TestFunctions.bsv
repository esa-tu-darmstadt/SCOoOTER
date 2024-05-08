package TestFunctions;

/*
  Functions for tests on vectors, structs and other types
*/

import Types :: *;
import Inst_Types :: *;
import Vector::*;
import Ehr::*;
import BUtils::*;

// get a reg interface from a creg/EHR. The interface implements one port of the CReg/EHR.
function a disassemble_creg(Integer num, Array#(a) creg);
    return creg[num];
endfunction

function Reg#(a) disassemble_ehr(Integer num, Ehr#(n, a) creg);
    return creg[num];
endfunction

// Find the n-th instance in a vector and return the index
//TODO: use less sequential algorithm
function UInt#(a) find_nth(UInt#(a) num, b cmp, Vector#(c, b) vec) provisos(
    Eq#(b)
);
    UInt#(a) found = 0;
    UInt#(a) out = 0;
    for(Integer i = 0; i < valueOf(c); i = i + 1) begin
        if(vec[i] == cmp) begin
            found = found + 1;
            if(found == num) out = fromInteger(i);
        end
    end
    return out;
endfunction

// same as above but using a valid bit in case nothing was found
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

// select program binary for simulation
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

function Bool ispwr2(Bit#(test) t_in);
    return (valueOf(TExp#(TLog#(test))) == valueOf(test));
endfunction

// get the value of an RWire
function Maybe#(a) get_r_wire(RWire#(a) rw) = rw.wget();

function UInt#(x) rollover_add(Bit#(test) t_in, UInt#(x) a, UInt#(x) b) provisos (
    Add#(x, 1, x_ext)
);
    if (ispwr2(t_in)) begin
        return a + b;
    end else begin 
        UInt#(x_ext) a_ext = cExtend(a);
        UInt#(x_ext) b_ext = cExtend(b);
        UInt#(x_ext) result_noroll = a_ext + b_ext;
        UInt#(x_ext) limit = fromInteger(valueOf(test));
        UInt#(x_ext) result_ext = (result_noroll >= limit ? result_noroll - limit : result_noroll);
        return cExtend(result_ext);
    end
    

endfunction

function Bit#(x) replicate_bit(Bit#(1) b);
    Bit#(x) out = 0;
    for (Integer i = 0; i < valueOf(x); i=i+1)
        out[i] = b;
    return out;
endfunction

endpackage

