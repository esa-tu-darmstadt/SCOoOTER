package ReservationStation;

import Interfaces :: *;
import List :: *;
import Inst_Types :: *;
import Vector :: *;
import Types :: *;
import List :: *;
import Debug::*;

module mkReservationStation#(ExecUnitTag eut, Vector#(size_res_bus_t, Maybe#(Result)) result_bus_vec)(ReservationStationIFC#(entries)) provisos (
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, entries_log_t),
    Log#(entries, entries_idx_t)
);

    function Bool isReady(Maybe#(Instruction) inst);
        return (inst matches tagged Valid .i &&& i.rs1 matches tagged Operand .v1 &&& i.rs2 matches tagged Operand .v2 ? True : False);
    endfunction

    //create a buffer of Instructions
    Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_v <- replicateM(mkReg(tagged Invalid));
    Vector#(entries, Maybe#(Instruction)) instruction_buffer_read_v = Vector::readVReg(instruction_buffer_v);

    rule listen_to_cdb;
        for(Integer i = 0; i < valueOf(size_res_bus_t); i=i+1) begin
            let current_result_maybe = result_bus_vec[i];

            if(current_result_maybe matches tagged Valid .current_result) begin
                let current_tag = current_result.tag;
                let current_val = current_result.result.Result;

                // test each instructions operands
                for(Integer j = 0; j < valueOf(entries); j=j+1) begin
                    let current_instruction = instruction_buffer_v[j];

                    if(current_instruction matches tagged Valid .inst) begin

                        let temp_inst = inst;
                        Bool changed = False;

                        //test rs1
                        if(inst.rs1 matches tagged Tag .t &&& t == current_tag) begin
                            temp_inst.rs1 = tagged Operand current_val;
                            changed = True;
                        end

                        //test rs2
                        if(inst.rs2 matches tagged Tag .t &&& t == current_tag) begin
                            temp_inst.rs2 = tagged Operand current_val;
                            changed = True;
                        end

                        instruction_buffer_v[j] <= tagged Valid temp_inst;

                    end

                end
            end
        end

    endrule

    Wire#(Instruction) inst_to_insert <- mkWire();
    Wire#(UInt#(entries_idx_t)) inst_to_insert_idx <- mkWire();

    rule insert_instruction;        
        instruction_buffer_v[inst_to_insert_idx] <= tagged Valid inst_to_insert;
        dbg_print(RS, $format("inserting inst: idx ", inst_to_insert_idx));
    endrule

    Wire#(UInt#(entries_idx_t)) clear_idx_w <- mkWire();

    (* conflict_free = "listen_to_cdb, insert_instruction, clear_instruction" *)
    rule clear_instruction;
        dbg_print(RS, $format("clearing inst: idx ", fshow(clear_idx_w)));
        instruction_buffer_v[clear_idx_w] <= tagged Invalid;
    endrule

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

    method Bool free = Vector::elem(tagged Invalid, readVReg(instruction_buffer_v));
    method ExecUnitTag unit_type = eut;
endmodule

endpackage