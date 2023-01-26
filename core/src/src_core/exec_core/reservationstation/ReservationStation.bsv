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
    ReservationStationIFC#(6) m <- mkLinearReservationStation(LS);
    return m;
endmodule

// Synthesizable wrappers
(* synthesize *)
module mkReservationStationMULDIV6(ReservationStationIFC#(6));
    ReservationStationIFC#(6) m <- mkReservationStation(MULDIV);
    return m;
endmodule

function Bool is_ready(Maybe#(Instruction) inst);
    return (inst matches tagged Valid .i &&& i.rs1 matches tagged Operand .v1 &&& i.rs2 matches tagged Operand .v2 ? True : False);
endfunction

module mkLinearReservationStation#(ExecUnitTag eut)(ReservationStationIFC#(entries)) provisos (
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, entries_log_t),
    Log#(entries, entries_idx_t),
    Add#(1, depth_dec_t, entries),
    Max#(1, depth_dec_t, depth_dec_pos_t),
    Log#(depth_dec_pos_t, depth_test_t)
);

    function UInt#(size_logidx_t) increment_index(UInt#(size_logidx_t) new_idx);
        UInt#(size_logidx_t) output_idx;
        //if DEPTH is not a pwr of two, explicitly implement rollover
        if( valueOf(entries_idx_t) == valueOf(depth_test_t) ) begin
            output_idx = new_idx == fromInteger(valueOf(entries)-1) ? 0 : new_idx + 1;
        // if depth is power of two, the index will roll over naturally
        end else output_idx = new_idx + 1;

        return output_idx;
    endfunction

    Wire#(Vector#(NUM_FU, Maybe#(Result))) result_bus_vec <- mkWire();


    Vector#(entries, Array#(Reg#(Maybe#(Instruction)))) instruction_buffer_v <- replicateM(mkCReg(2, tagged Invalid));
    Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_port0_v = Vector::map(disassemble_creg(0), instruction_buffer_v);
    Vector#(entries, Reg#(Maybe#(Instruction))) instruction_buffer_port1_v = Vector::map(disassemble_creg(1), instruction_buffer_v);

    Reg#(UInt#(entries_idx_t)) head_r <- mkReg(0);
    Reg#(UInt#(entries_idx_t)) tail_r <- mkReg(0);

    Reg#(Bool) full_r[2] <- mkCReg(2, False);

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

    let instruction_buffer_read_v = Vector::readVReg(instruction_buffer_port0_v);

    PulseWire clear_full_flag_w <- mkPulseWire();
    Wire#(Instruction) inst_to_insert <- mkWire();

    rule insert_inst;
        instruction_buffer_port1_v[head_r] <= tagged Valid inst_to_insert;
        head_r <= increment_index(head_r);
        if(tail_r == increment_index(head_r)) full_r[0] <= True;
    endrule

    rule clear_full_flag if(clear_full_flag_w);
        full_r[1] <= False;
        tail_r <= increment_index(tail_r);
    endrule

    method ActionValue#(Instruction) get if (
            (head_r != tail_r || full_r[0]) && 
            is_ready(instruction_buffer_read_v[tail_r])
        );
        let inst = fromMaybe(?, instruction_buffer_read_v[tail_r]);
        clear_full_flag_w.send();
        dbg_print(RS, $format("dequeueing inst: idx ", fshow(inst)));
        return inst;
    endmethod

    method ExecUnitTag unit_type = eut;

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);
        result_bus_vec <= bus_in;
    endmethod

    interface ReservationStationPutIFC in;
        interface Put instruction;
            method Action put(Instruction inst);// if (!full_r[0]);
                inst_to_insert <= inst;
            endmethod
        endinterface
        method Bool can_insert = !full_r[0];
    endinterface
endmodule


module mkReservationStation#(ExecUnitTag eut)(ReservationStationIFC#(entries)) provisos (
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, entries_log_t),
    Log#(entries, entries_idx_t)
);

    Wire#(Vector#(NUM_FU, Maybe#(Result))) result_bus_vec <- mkWire();

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

    method ActionValue#(Instruction) get if (Vector::any(is_ready, instruction_buffer_read_v));
        let idx = fromMaybe(?, Vector::findIndex(is_ready, instruction_buffer_read_v));
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
            method Action put(Instruction inst);// if (Vector::elem(tagged Invalid, instruction_buffer_read_v));
                inst_to_insert <= inst;
                inst_to_insert_idx <= Vector::findElem(tagged Invalid, instruction_buffer_read_v).Valid;
                dbg_print(RS, $format("got inst: ", fshow(inst)));
            endmethod
        endinterface
        method Bool can_insert = Vector::elem(tagged Invalid, instruction_buffer_read_v);
    endinterface
endmodule

endpackage