package ReservationStation;

import Interfaces::*;
import Inst_Types::*;
import Vector::*;
import Types::*;
import Debug::*;
import TestFunctions::*;
import GetPut::*;


// Synthesizable wrappers
(* synthesize *)
module mkReservationStationALU6(ReservationStationIFC#(6));
    ReservationStationIFC#(6) m <- mkReservationStation(ALU);
    return m;
endmodule

// Synthesizable wrappers
(* synthesize *)
module mkReservationStationBR6(ReservationStationIFC#(6));
    ReservationStationIFC#(6) m <- mkReservationStation(BR);
    return m;
endmodule

// Synthesizable wrappers
(* synthesize *)
module mkReservationStationMEM6(ReservationStationIFC#(6));
    ReservationStationIFC#(6) m <- mkReservationStation(LS);
    return m;
endmodule

// Synthesizable wrappers
(* synthesize *)
module mkReservationStationMULDIV6(ReservationStationIFC#(6));
    ReservationStationIFC#(6) m <- mkReservationStation(MULDIV);
    return m;
endmodule

module mkReservationStation#(ExecUnitTag eut)(ReservationStationIFC#(entries)) provisos (
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, entries_log_t),
    Log#(entries, entries_idx_t)
);

    Wire#(Vector#(NUM_FU, Maybe#(Result))) result_bus_vec <- mkWire();

    function Bool isReady(Maybe#(Instruction) inst);
        return (inst matches tagged Valid .i &&& i.rs1 matches tagged Operand .v1 &&& i.rs2 matches tagged Operand .v2 ? True : False);
    endfunction

    //create a buffer of Instructions
    //Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_v <- replicateM(mkReg(tagged Invalid));
    Vector#(entries, Array#(Reg#(Maybe#(Instruction)))) instruction_buffer_v <- replicateM(mkCReg(2, tagged Invalid));
    Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_port0_v = Vector::map(disassemble_creg(0), instruction_buffer_v);
    Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_port1_v = Vector::map(disassemble_creg(1), instruction_buffer_v);

    rule print_innards;
        for(Integer i = 0; i < valueOf(entries); i=i+1) begin
            dbg_print(RS, $format("ROB ", fshow(eut), " ", i, " ", fshow(instruction_buffer_port1_v[i])));
        end
    endrule

    rule listen_to_cdb;
        for(Integer j = 0; j < valueOf(entries); j=j+1) begin

            if(instruction_buffer_port0_v[j] matches tagged Valid .inst) begin
                Instruction current_instruction = inst;

                for(Integer i = 0; i < valueOf(NUM_FU); i=i+1) begin
                    if( result_bus_vec[i] matches tagged Valid .res &&&
                        current_instruction.rs1 matches tagged Tag .t &&& 
                        t == res.tag)
                        current_instruction.rs1 = tagged Operand res.result.Result;

                    if( result_bus_vec[i] matches tagged Valid .res &&&
                        current_instruction.rs2 matches tagged Tag .t &&& 
                        t == res.tag)
                        current_instruction.rs2 = tagged Operand res.result.Result;
                end

                instruction_buffer_port0_v[j] <= tagged Valid current_instruction;
            end
        end
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

    method ActionValue#(Instruction) get if (Vector::any(isReady, instruction_buffer_read_v));
        let idx = fromMaybe(?, Vector::findIndex(isReady, instruction_buffer_read_v));
        let inst = fromMaybe(?, instruction_buffer_read_v[idx]);
        clear_idx_w <= idx;
        dbg_print(RS, $format("dequeueing inst: idx ", fshow(idx)));
        return inst;
    endmethod

    method ExecUnitTag unit_type = eut;

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);
        result_bus_vec <= bus_in;
    endmethod

    interface ReservationStationPutIFC in;
        interface Put instruction;
            method Action put(Instruction inst) if (Vector::elem(tagged Invalid, instruction_buffer_read_v));
                inst_to_insert <= inst;
                inst_to_insert_idx <= Vector::findElem(tagged Invalid, instruction_buffer_read_v).Valid;
            endmethod
        endinterface
        method Bool can_insert = Vector::elem(tagged Invalid, instruction_buffer_read_v);
    endinterface
endmodule

endpackage