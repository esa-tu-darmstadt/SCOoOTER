package TestFunctions;

import Types :: *;
import Inst_Types :: *;

function Instruction squash_operands(Instruction inst);
    if(inst.rs1 matches tagged Raddr .r &&& r == 0)
        inst.rs1 = tagged Operand 0;
    if(inst.rs2 matches tagged Raddr .r &&& r == 0)
        inst.rs2 = tagged Operand 0;

    return inst;
endfunction

function a disassemble_creg(Integer num, Array#(a) creg);
    return creg[num];
endfunction

endpackage