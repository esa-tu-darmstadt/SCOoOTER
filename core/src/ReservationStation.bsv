package ReservationStation;

import Interfaces :: *;
import List :: *;
import Inst_Types :: *;
import Vector :: *;
import Types :: *;
import List :: *;
import Debug::*;
import TestFunctions::*;

module mkReservationStation#(ExecUnitTag eut, Vector#(size_res_bus_t, Maybe#(Result)) result_bus_vec)(ReservationStationIFC#(entries)) provisos (
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, entries_log_t),
    Log#(entries, entries_idx_t)
);

    function Bool isReady(Maybe#(Instruction) inst);
        return (inst matches tagged Valid .i &&& i.rs1 matches tagged Operand .v1 &&& i.rs2 matches tagged Operand .v2 ? True : False);
    endfunction

    //create a buffer of Instructions
    //Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_v <- replicateM(mkReg(tagged Invalid));
    Vector#(entries, Array#(Reg#(Maybe#(Instruction)))) instruction_buffer_v <- replicateM(mkCReg(2, tagged Invalid));
    Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_port0_v = Vector::map(disassemble_creg(0), instruction_buffer_v);
    Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_port1_v = Vector::map(disassemble_creg(1), instruction_buffer_v);

    rule listen_to_cdb;
        let instructions_to_update = Vector::readVReg(instruction_buffer_port0_v);

        for(Integer i = 0; i < valueOf(size_res_bus_t); i=i+1) begin
            let current_result_maybe = result_bus_vec[i];

            if(current_result_maybe matches tagged Valid .current_result) begin
                let current_tag = current_result.tag;
                let current_val = current_result.result.Result;

                // test each instructions operands
                for(Integer j = 0; j < valueOf(entries); j=j+1) begin
                    let current_instruction = instructions_to_update[j];

                    if(current_instruction matches tagged Valid .inst) begin

                        //test rs1
                        if(inst.rs1 matches tagged Tag .t &&& t == current_tag) begin
                            //instructions_to_update[j].Valid.rs1 = tagged Operand current_val;
                        end

                        //test rs2
                        if(inst.rs2 matches tagged Tag .t &&& t == current_tag) begin
                            //instructions_to_update[j].Valid.rs2 = tagged Operand current_val;
                        end
                    end

                end
            end
        end

        Vector::writeVReg(instruction_buffer_port0_v, instructions_to_update);

    endrule

    Wire#(Instruction) inst_to_insert <- mkWire();
    Wire#(UInt#(entries_idx_t)) inst_to_insert_idx <- mkWire();

    rule insert_instruction;        
        instruction_buffer_port1_v[inst_to_insert_idx] <= tagged Valid inst_to_insert;
        dbg_print(RS, $format("inserting inst: idx ", inst_to_insert_idx));
    endrule

    Wire#(UInt#(entries_idx_t)) clear_idx_w <- mkWire();

    (* conflict_free = "listen_to_cdb, insert_instruction, clear_instruction" *)
    rule clear_instruction;
        dbg_print(RS, $format("clearing inst: idx ", fshow(clear_idx_w)));
        instruction_buffer_port1_v[clear_idx_w] <= tagged Invalid;
    endrule

    let instruction_buffer_read_v = Vector::readVReg(instruction_buffer_port0_v);

    //TODO: test CDB here as well or do not latch in issue stage
    method Action put(Instruction inst) if (Vector::elem(tagged Invalid, instruction_buffer_read_v));
        inst_to_insert <= inst;
        inst_to_insert_idx <= Vector::findElem(tagged Invalid, instruction_buffer_read_v).Valid;
    endmethod

    method ActionValue#(Instruction) get if (Vector::any(isReady, instruction_buffer_read_v));
        let idx = fromMaybe(?, Vector::findIndex(isReady, instruction_buffer_read_v));
        let inst = fromMaybe(?, instruction_buffer_read_v[idx]);
        clear_idx_w <= idx;
        dbg_print(RS, $format("dequeueing inst: idx ", fshow(idx)));
        return inst;
    endmethod

    method Bool free = Vector::elem(tagged Invalid, instruction_buffer_read_v);
    method ExecUnitTag unit_type = eut;
endmodule

endpackage