package ReservationStation;

import Interfaces :: *;
import List :: *;
import Inst_Types :: *;
import Vector :: *;
import Types :: *;
import List :: *;

module mkReservationStation#(List#(OpCode) operations)(ReservationStationIFC#(addrwidth, entries)) provisos (
    Add#(a__, TLog#(TAdd#(1, entries)), addrwidth) //TODO: fancify
);

    function Reg#(Maybe#(Instruction)) getEntry(Integer part, Array#(Reg#(Maybe#(Instruction))) element);
        return element[part];
    endfunction

    function Bool isReady(Maybe#(Instruction) inst);
        return (inst matches tagged Valid .i &&& inst.Valid.rs1 matches tagged Operand .v1 &&& inst.Valid.rs2 matches tagged Operand .v2 ? True : False);
    endfunction

    //create a buffer of Instructions
    Vector#(entries, Array#(Reg#(Maybe#(Instruction)))) instruction_buffer_v <- replicateM(mkCReg(3, tagged Invalid));
    Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_extract_v = map(getEntry(0), instruction_buffer_v);
    // TODO: latch operands
    Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_operands_v = map(getEntry(1), instruction_buffer_v);
    Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_insert_v = map(getEntry(2), instruction_buffer_v);

    method Action put(Vector#(ISSUEWIDTH, Instruction) inst, MIMO::LUInt#(ISSUEWIDTH) count);
        Vector#(entries, Maybe#(Instruction)) instdata = readVReg(instruction_buffer_insert_v);
        for(Integer i = 0; i<valueOf(ISSUEWIDTH) && fromInteger(i)<count; i=i+1) begin
            let idx = fromMaybe(?, Vector::findElem(tagged Invalid, instdata));
            instdata[idx] = tagged Valid inst[i];
            $display("[RS]: got ", fshow(inst[i]));
        end
        writeVReg(instruction_buffer_insert_v, instdata);
    endmethod

    method ActionValue#(Instruction) get if (Vector::any(isReady, readVReg(instruction_buffer_extract_v)));
        Vector#(entries, Maybe#(Instruction)) instdata = readVReg(instruction_buffer_extract_v);
        let idx = fromMaybe(?, Vector::findIndex(isReady, instdata));
        let inst = fromMaybe(?, instdata[idx]);
        instdata[idx] = tagged Invalid;
        writeVReg(instruction_buffer_extract_v, instdata);
        return inst;
    endmethod

    interface free = extend(Vector::countElem(tagged Invalid, readVReg(instruction_buffer_insert_v)));
    interface supported_opc = operations;
endmodule

endpackage