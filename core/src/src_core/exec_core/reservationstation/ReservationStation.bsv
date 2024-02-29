package ReservationStation;

/*
  ReservationStations are the buffers between ISSUE and any FU.
  The buffers hold instructions and latch values.

  Linear RS keep the instructions in order, which is important for
  e.g. Memory. Normal RS reorder the instructions.
*/

import Interfaces::*;
import Inst_Types::*;
import Vector::*;
import Types::*;
import Debug::*;
import TestFunctions::*;
import GetPut::*;
import Ehr::*;
import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;

// interface for the wrappers
// the wrappers abstract the depth of the RS
// such that the interface of any depth is similar
interface ReservationStationWrIFC;
    method ActionValue#(InstructionIssue) get;
    interface ReservationStationPutIFC in;
    (* always_ready, always_enabled *)
    method ExecUnitTag unit_type;
    (* always_ready, always_enabled *)
    method Action result_bus(Vector#(NUM_FU, Maybe#(ResultLoopback)) bus_in);
endinterface

// Wrappers for different Unit types

// Synthesizable wrappers
`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkReservationStationCSR(ReservationStationWrIFC);
    ReservationStationIFC#(RS_DEPTH_CSR) m <- mkLinearReservationStation(CSR);
    interface get = m.get;
    interface in = m.in;
    interface unit_type = m.unit_type;
    interface result_bus = m.result_bus;
endmodule

// Synthesizable wrappers
`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkReservationStationALU(ReservationStationWrIFC);
    ReservationStationIFC#(RS_DEPTH_ALU) m <- mkReservationStation(ALU);
    interface get = m.get;
    interface in = m.in;
    interface unit_type = m.unit_type;
    interface result_bus = m.result_bus;
endmodule

// Synthesizable wrappers
`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkReservationStationBR(ReservationStationWrIFC);
    ReservationStationIFC#(RS_DEPTH_BR) m <- mkReservationStation(BR);
    interface get = m.get;
    interface in = m.in;
    interface unit_type = m.unit_type;
    interface result_bus = m.result_bus;
endmodule

// Synthesizable wrappers
`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkReservationStationMEM(ReservationStationWrIFC);
    ReservationStationIFC#(RS_DEPTH_MEM) m <- mkLinearReservationStation(LS);
    interface get = m.get;
    interface in = m.in;
    interface unit_type = m.unit_type;
    interface result_bus = m.result_bus;
endmodule

// Synthesizable wrappers
`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkReservationStationMULDIV(ReservationStationWrIFC);
    ReservationStationIFC#(RS_DEPTH_MULDIV) m <- mkReservationStation(MULDIV);
    interface get = m.get;
    interface in = m.in;
    interface unit_type = m.unit_type;
    interface result_bus = m.result_bus;
endmodule

function Bool is_ready(Maybe#(InstructionIssue) inst);
    return (inst matches tagged Valid .i &&& i.rs1 matches tagged Operand .v1 &&& i.rs2 matches tagged Operand .v2 ? True : False);
endfunction

// Linear RS
module mkLinearReservationStation#(ExecUnitTag eut)(ReservationStationIFC#(entries)) provisos (
    // types to track fullness and index
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, entries_log_t),
    Log#(entries, entries_idx_t),
    Add#(a__, entries_idx_t, entries_log_t)
);
    // implement idx rollover
    function UInt#(size_logidx_t) increment_index(UInt#(size_logidx_t) new_idx);
        UInt#(size_logidx_t) output_idx;
        //if DEPTH is not a pwr of two, explicitly implement rollover
        Bit#(entries) dummy = 0;
        if( !ispwr2(dummy) ) begin
            output_idx = (new_idx == fromInteger(valueOf(entries)-1) ? 0 : (new_idx + 1));
        // if depth is power of two, the index will roll over naturally
        end else output_idx = new_idx + 1;
        return output_idx;
    endfunction

    // wire to transport result bus
    Reg#(Vector#(NUM_FU, Maybe#(ResultLoopback))) result_bus_vec <- (valueOf(RS_LATCH_INPUT) == 1 ? mkRegU() : mkBypassWire());
    Reg#(Vector#(NUM_FU, Maybe#(ResultLoopback))) result_bus_bypass <- mkBypassWire();
    rule propagate_res_bus;
        result_bus_vec <= result_bus_bypass;
    endrule

    // internal storage
    Vector#(entries, Reg#(Maybe#(InstructionIssue))) instruction_buffer_v <- replicateM(mkReg(tagged Invalid));
    // head, tail and full pointers
    Reg#(UInt#(entries_idx_t)) head_r <- mkReg(0);
    Reg#(UInt#(entries_idx_t)) tail_r <- mkReg(0);
    Reg#(Bool) full_r[2] <- mkCReg(2, False);

    function UInt#(entries_log_t) empty_slots;
        UInt#(entries_log_t) result;

        //calculate from head and tail pointers
        if (head_r > tail_r) result = extend(head_r) - extend(tail_r);
        else if (tail_r > head_r) result = fromInteger(valueOf(entries)) - extend(tail_r) + extend(head_r);
        // if both pointers are equal, must be full or empty
        else if (full_r[0]) result = fromInteger(valueOf(entries));
        else result = 0;

        return fromInteger(valueOf(entries)) - result;
    endfunction

    rule print_innards;
        let idx = tail_r;
        Bool nodone = True;
        for(Integer i = 0; i < valueOf(entries); i=i+1) 
        if ((tail_r != head_r || full_r[0]) && nodone) begin
            dbg_print(RS, $format(fshow(eut), " ", i, " ", fshow(instruction_buffer_v[idx])));
            if (idx == head_r) nodone = False;            
        end
    endrule

    // evaluate result bus
    rule listen_to_cdb;
        for(Integer j = 0; j < valueOf(entries); j=j+1) begin // loop over entries

            if(instruction_buffer_v[j] matches tagged Valid .inst) begin
                InstructionIssue current_instruction = inst;

                Bool change = False;

                // loop pver result bus
                for(Integer i = 0; i < valueOf(NUM_FU); i=i+1) begin
                    // update rs1
                    if( result_bus_vec[i] matches tagged Valid .res &&&
                        current_instruction.rs1 matches tagged Tag .t &&& 
                        t == res.tag) begin
                            current_instruction.rs1 = tagged Operand res.result;
                            change = True;
                        end
                    // update rs2
                    if( result_bus_vec[i] matches tagged Valid .res &&&
                        current_instruction.rs2 matches tagged Tag .t &&& 
                        t == res.tag) begin
                            current_instruction.rs2 = tagged Operand res.result;
                            change = True;
                        end
                end

                if (change) instruction_buffer_v[j] <= tagged Valid current_instruction;
            end
        end
    endrule

    // update the tail pointer if an inst gets dequeued
    PulseWire clear_full_flag_w <- mkPulseWire();
    rule clear_full_flag if(clear_full_flag_w);
        full_r[1] <= False;
        tail_r <= increment_index(tail_r);
    endrule

    PulseWire has_enq <- mkPulseWire();

    `ifdef LOG_PIPELINE
        Reg#(UInt#(XLEN)) clk_ctr <- mkReg(0);
        rule count_clk; clk_ctr <= clk_ctr + 1; endrule
        Reg#(File) out_log <- mkRegU();
        Reg#(File) out_log_ko <- mkRegU();
        rule open if (clk_ctr == 0);
            File out_log_l <- $fopen("scoooter.log", "a");
            out_log <= out_log_l;
            File out_log_kol <- $fopen("konata.log", "a");
            out_log_ko <= out_log_kol;
        endrule
    `endif

    FIFOF#(InstructionIssue) inst_to_enqueue <- (valueOf(RS_LATCH_INPUT) == 1 ? mkPipelineFIFOF() : mkBypassFIFOF());

    (* conflict_free="enqueue, listen_to_cdb" *)
    rule enqueue;
        instruction_buffer_v[head_r] <= tagged Valid inst_to_enqueue.first();
        inst_to_enqueue.deq();
        let new_head = increment_index(head_r);
        head_r <= new_head;
        if(tail_r == new_head) full_r[0] <= True;
    endrule

    Reg#(Bool) ready_r <- mkReg(True);
    PulseWire will_insert_next <- mkPulseWire();
    Wire#(Bool) will_insert_now <- mkBypassWire();
    Wire#(UInt#(entries_log_t)) free_slots_w <- mkBypassWire();
    rule insert_now; will_insert_now <= inst_to_enqueue.notEmpty(); endrule
    rule empty_calc; free_slots_w <= empty_slots(); endrule
        
    rule calc_next_rdy;
        let insert_currently = will_insert_now;
        let insert_next = will_insert_next;

        Integer cmp = insert_currently && insert_next && (valueOf(RS_LATCH_INPUT) == 1) ? 2 :
                      insert_currently || insert_next ? 1 : 0;

        ready_r <= free_slots_w > fromInteger(cmp);
    endrule

    // dequeue an instruction if one is ready
    method ActionValue#(InstructionIssue) get if (
            (head_r != tail_r || full_r[0]) && 
            is_ready(instruction_buffer_v[tail_r])
        );
        let inst = fromMaybe(?, instruction_buffer_v[tail_r]);
        clear_full_flag_w.send();
        dbg_print(RS, $format("dequeueing inst: idx ", fshow(inst)));
        `ifdef LOG_PIPELINE
            $fdisplay(out_log, "%d DISPATCH %x %d %d", clk_ctr, inst.pc, inst.tag, inst.epoch);
            $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, inst.log_id, 0, "S");
        `endif
        return inst;
    endmethod

    // provide the unit type
    method ExecUnitTag unit_type = eut;

    // input the result bus
    method Action result_bus(Vector#(NUM_FU, Maybe#(ResultLoopback)) bus_in) = result_bus_bypass._write(bus_in);

    // input instructions to RS
    interface ReservationStationPutIFC in;
        interface Put instruction;
            method Action put(InstructionIssue inst);
                will_insert_next.send();
                inst_to_enqueue.enq(inst);
            endmethod
        endinterface
        method Bool can_insert = ready_r;
    endinterface
endmodule


module mkReservationStation#(ExecUnitTag eut)(ReservationStationIFC#(entries)) provisos (
    // create index and count types
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, entries_log_t),
    Log#(entries, entries_idx_t),
    Add#(a__, 1, entries_log_t)
);

    // wire to distribute result bus
    Reg#(Vector#(NUM_FU, Maybe#(ResultLoopback))) result_bus_vec <- (valueOf(RS_LATCH_INPUT) == 1 ? mkReg(replicate(tagged Invalid)) : mkBypassWire());

    //create a buffer of Instructions
    Vector#(entries, Reg#(Maybe#(InstructionIssue))) instruction_buffer_v <- replicateM(mkReg(tagged Invalid));

    // print contents for debugging
    rule print_innards;
        for(Integer i = 0; i < valueOf(entries); i=i+1) begin
            dbg_print(RS, $format(fshow(eut), " ", i, " ", fshow(instruction_buffer_v[i])));
        end
    endrule

    Wire#(Vector#(entries, Maybe#(InstructionIssue))) instruction_buffer_preread <- mkBypassWire();
    rule preread;
        instruction_buffer_preread <= Vector::readVReg(instruction_buffer_v);
    endrule

    // evaluate result bus
    rule listen_to_cdb;
        for(Integer j = 0; j < valueOf(entries); j=j+1) begin // loop over entries

            if(instruction_buffer_preread[j] matches tagged Valid .inst) begin
                InstructionIssue current_instruction = inst;
                Bool chg = False;

                // loop pver result bus
                for(Integer i = 0; i < valueOf(NUM_FU); i=i+1) begin
                    // update rs1
                    if( result_bus_vec[i] matches tagged Valid .res &&&
                        current_instruction.rs1 matches tagged Tag .t &&& 
                        t == res.tag) begin
                            current_instruction.rs1 = tagged Operand res.result;
                            chg = True;
                        end
                    // update rs2
                    if( result_bus_vec[i] matches tagged Valid .res &&&
                        current_instruction.rs2 matches tagged Tag .t &&& 
                        t == res.tag) begin
                            current_instruction.rs2 = tagged Operand res.result;
                            chg = True;
                        end
                end

                if(chg) instruction_buffer_v[j] <= tagged Valid current_instruction;
            end
        end
    endrule

    // insert instruction, wires will be written by method
    FIFOF#(InstructionIssue) inst_to_insert <- valueOf(RS_LATCH_INPUT) == 1 ? mkPipelineFIFOF() : mkBypassFIFOF();
    rule insert_instruction;
        let inst = inst_to_insert.first();
        inst_to_insert.deq();
        let inst_to_insert_idx = Vector::findElem(tagged Invalid, instruction_buffer_preread).Valid;
        instruction_buffer_v[inst_to_insert_idx] <= tagged Valid inst;
        dbg_print(RS, $format("inserting inst: idx ", inst_to_insert_idx));
    endrule

    // dequeue an instruction if it was retrieved
    Wire#(UInt#(entries_idx_t)) clear_idx_w <- mkWire();
    (* conflict_free = "listen_to_cdb, insert_instruction, clear_instruction" *)
    rule clear_instruction;
        dbg_print(RS, $format("clearing inst: idx ", fshow(clear_idx_w)));
        instruction_buffer_v[clear_idx_w] <= tagged Invalid;
    endrule

    `ifdef LOG_PIPELINE
        Reg#(UInt#(XLEN)) clk_ctr <- mkReg(0);
        rule count_clk; clk_ctr <= clk_ctr + 1; endrule
        Reg#(File) out_log <- mkRegU();
        Reg#(File) out_log_ko <- mkRegU();
        rule open if (clk_ctr == 0);
            File out_log_l <- $fopen("scoooter.log", "a");
            out_log <= out_log_l;
            File out_log_kol <- $fopen("konata.log", "a");
            out_log_ko <= out_log_kol;
        endrule
    `endif

    Reg#(Bool) can_insert_buffer <- mkReg(True);
    PulseWire will_insert_next <- mkPulseWire();
    Wire#(Bool) will_insert_now <- mkBypassWire();
    rule insert_now; will_insert_now <= inst_to_insert.notEmpty(); endrule
    rule calculate_next_insert;

        let free_slots = Vector::countElem(tagged Invalid, instruction_buffer_preread);
        let insert_currently = will_insert_now;
        let insert_next = will_insert_next;

        Integer cmp = insert_currently && insert_next && (valueOf(RS_LATCH_INPUT) == 1) ? 2 :
                      insert_currently || insert_next ? 1 : 0;

        can_insert_buffer <= free_slots > fromInteger(cmp);
    endrule

    FIFO#(InstructionIssue) inst_out_buf <- mkPipelineFIFO();

    Vector#(entries, Maybe#(InstructionIssue)) instruction_buffer_read_v = Vector::readVReg(instruction_buffer_v);
    rule collect_rdy if (Vector::any(is_ready, instruction_buffer_read_v));
        let idx = fromMaybe(?, Vector::findIndex(is_ready, instruction_buffer_read_v));
        let inst = fromMaybe(?, instruction_buffer_read_v[idx]);
        clear_idx_w <= idx;
        dbg_print(RS, $format("dequeueing inst: idx ", fshow(idx)));
        `ifdef LOG_PIPELINE
            $fdisplay(out_log, "%d DISPATCH %x %d %d", clk_ctr, inst.pc, inst.tag, inst.epoch);
            $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, inst.log_id, 0, "S");
        `endif
        inst_out_buf.enq(inst);
    endrule

    // method to request an instruction
    method ActionValue#(InstructionIssue) get;
        inst_out_buf.deq();
        return inst_out_buf.first();
    endmethod

    // return execution unit tag
    method ExecUnitTag unit_type = eut;

    // input result bus
    method Action result_bus(Vector#(NUM_FU, Maybe#(ResultLoopback)) bus_in) = result_bus_vec._write(bus_in);

    // insert instructions
    interface ReservationStationPutIFC in;
        interface Put instruction;
            method Action put(InstructionIssue inst);
                inst_to_insert.enq(inst);
                will_insert_next.send();
                dbg_print(RS, $format("got inst: ", fshow(inst)));
            endmethod
        endinterface
        method Bool can_insert = can_insert_buffer;
    endinterface
endmodule

endpackage