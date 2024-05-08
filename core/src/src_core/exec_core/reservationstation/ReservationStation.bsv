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
    ReservationStationIFC#(RS_DEPTH_CSR) m <- mkLinearReservationStation_simple(CSR);
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
    ReservationStationIFC#(RS_DEPTH_ALU) m <- mkReservationStation_simple(ALU);
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
    ReservationStationIFC#(RS_DEPTH_BR) m <- mkReservationStation_simple(BR);
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
    ReservationStationIFC#(RS_DEPTH_MEM) m <- mkLinearReservationStation_simple(LS);
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
    ReservationStationIFC#(RS_DEPTH_MULDIV) m <- mkReservationStation_simple(MULDIV);
    interface get = m.get;
    interface in = m.in;
    interface unit_type = m.unit_type;
    interface result_bus = m.result_bus;
endmodule

interface RSRowIfc;
    method Bool full;
    method Bool ready;
    method Action in(InstructionIssue i);
    method ActionValue#(InstructionIssue) out;
    (*always_ready, always_enabled*)
    method Action result_bus(Vector#(NUM_FU, Maybe#(ResultLoopback)) bus_in);
endinterface

function Bool is_occupied(RSRowIfc r) = r.full;
function Bool is_free(RSRowIfc r) = !r.full;
function Bool is_ready(RSRowIfc r) = r.ready;

module mkRSRow(RSRowIfc);
    Reg#(InstructionIssue) entry <- mkRegU;
    Array#(Reg#(Bool)) full_r <- mkCReg(2, False);
    Array#(Reg#(Maybe#(Bit#(32)))) op1 <- mkCReg(2, tagged Invalid);
    Array#(Reg#(Maybe#(Bit#(32)))) op2 <- mkCReg(2, tagged Invalid);
    Reg#(Vector#(NUM_FU, Maybe#(ResultLoopback))) result_bus_vec <- (valueOf(RS_LATCH_INPUT) == 1 ? mkRegU() : mkBypassWire());

    function Bool match_tag(UInt#(TLog#(ROBDEPTH)) tag, Maybe#(ResultLoopback) r) = isValid(r) && r.Valid.tag == tag;
    rule consume_result_bus;
        if (entry.rs1 matches tagged Tag .t) begin
            let r1 = Vector::find(match_tag(t), result_bus_vec);
            if (r1 matches tagged Valid .r &&& op1[0] matches tagged Invalid) begin
                op1[0] <= tagged Valid r.Valid.result;
            end
        end

        if (entry.rs2 matches tagged Tag .t) begin
            let r2 = Vector::find(match_tag(t), result_bus_vec);
            if (r2 matches tagged Valid .r &&& op2[0] matches tagged Invalid) begin
                op2[0] <= tagged Valid r.Valid.result;
            end
        end
    endrule

    // use wires to allow for more dynamic scheduling of interface methods
    Wire#(Bool) full_w <- mkBypassWire();
    Wire#(Bool) ready_w <- mkBypassWire();
    rule bypass_ifc; full_w <= full_r[0]; ready_w <= full_r[0] && isValid(op1[0]) && isValid(op2[0]); endrule
    
    method Bool full = full_w;
    method Bool ready = ready_w;
    
    // an instruction enters the RS
    // Set up the operand registers
    method Action in(InstructionIssue i);
        entry <= i;
        full_r[1] <= True;
        if (i.rs1 matches tagged Operand .o)
            op1[1] <= tagged Valid o;
        else
            op1[1] <= tagged Invalid;
        if (i.rs2 matches tagged Operand .o)
            op2[1] <= tagged Valid o;
        else
            op2[1] <= tagged Invalid;
    endmethod

    // retrieve an instruction
    // update the operands with the gathered ones
    method ActionValue#(InstructionIssue) out;
        full_r[0] <= False;
        let e = entry;
        e.rs1 = tagged Operand op1[0].Valid;
        e.rs2 = tagged Operand op2[0].Valid;
        return e;
    endmethod
    method Action result_bus(Vector#(NUM_FU, Maybe#(ResultLoopback)) bus_in) = result_bus_vec._write(bus_in);
endmodule




module mkReservationStation_simple#(ExecUnitTag eut)(ReservationStationIFC#(entries)) provisos (
    // create index and count types
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, entries_log_t),
    Log#(entries, entries_idx_t),
    Add#(a__, 1, entries_log_t)
);

    // create a buffer of Instructions
    Vector#(entries, RSRowIfc) rows <- replicateM(mkRSRow);

    FIFO#(InstructionIssue) inst_in_f <- mkPipelineFIFO();
    rule insert_inst if (valueOf(RS_LATCH_INPUT) == 1);
        Vector::find(is_free, rows).Valid.in(inst_in_f.first());

        dbg_print(RS, $format("got: ", fshow(inst_in_f.first())));

        // error handling
        if(Vector::find(is_free, rows) matches tagged Invalid) begin
            $display("Trying to enqueue into already full RS! Abort!");
            $finish;
        end

        inst_in_f.deq();
    endrule

    // result bus
    Reg#(Vector#(NUM_FU, Maybe#(ResultLoopback))) result_bus_vec <- valueOf(SPLIT_ISSUE_STAGE) == 1 ? mkRegU() : mkBypassWire();
    rule forward_results;
        for(Integer i = 0; i < valueOf(entries); i=i+1)
            rows[i].result_bus(result_bus_vec);
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

    // method to request an instruction
    method ActionValue#(InstructionIssue) get if (Vector::any(is_ready, rows));
        let i <- Vector::find(is_ready, rows).Valid.out();

        `ifdef LOG_PIPELINE
            $fdisplay(out_log, "%d DISPATCH %x %d %d", clk_ctr, i.pc, i.tag, i.epoch);
            $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, i.log_id, 0, "S");
        `endif

        return i;
    endmethod

    // return execution unit tag
    method ExecUnitTag unit_type = eut;

    // input result bus
    method Action result_bus(Vector#(NUM_FU, Maybe#(ResultLoopback)) bus_in) = result_bus_vec._write(bus_in);

    // insert instructions
    interface ReservationStationPutIFC in;
        interface Put instruction;
            method Action put(InstructionIssue inst);
                if (valueOf(RS_LATCH_INPUT) == 0) begin
                    Vector::find(is_free, rows).Valid.in(inst);

                    if(Vector::find(is_free, rows) matches tagged Invalid) begin
                        $display("Trying to enqueue inro already full RS! Abort!");
                        $finish;
                    end
                end else begin
                    inst_in_f.enq(inst);
                end
                dbg_print(RS, $format("got inst: ", fshow(inst)));
            endmethod
        endinterface
        method Bool can_insert;
            Integer free_slots = fromInteger(valueOf(RS_LATCH_INPUT)) + fromInteger(valueOf(SPLIT_ISSUE_STAGE)) + 1;
            return free_slots == 1 ? Vector::any(is_free, rows) : (Vector::countIf(is_free, rows) >= fromInteger(free_slots));
        endmethod
    endinterface
endmodule

module mkLinearReservationStation_simple#(ExecUnitTag eut)(ReservationStationIFC#(entries)) provisos (
    // create index and count types
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, entries_log_t),
    Log#(entries, entries_idx_t),
    Add#(a__, 1, entries_log_t)
);

    Reg#(UInt#(entries_idx_t)) head_r <- mkReg(0);
    Reg#(UInt#(entries_idx_t)) tail_r <- mkReg(0);

    // create a buffer of Instructions
    Vector#(entries, RSRowIfc) rows <- replicateM(mkRSRow);

    FIFO#(InstructionIssue) inst_in_f <- mkPipelineFIFO();
    rule insert_inst if (valueOf(RS_LATCH_INPUT) == 1);
        rows[head_r].in(inst_in_f.first());
        Bit#(entries) dummy = 0;
        head_r <= rollover_add(dummy, head_r, 1);
        inst_in_f.deq();
    endrule

    // result bus
    Reg#(Vector#(NUM_FU, Maybe#(ResultLoopback))) result_bus_vec <- valueOf(SPLIT_ISSUE_STAGE) == 1 ? mkRegU() : mkBypassWire();
    rule forward_results;
        for(Integer i = 0; i < valueOf(entries); i=i+1)
            rows[i].result_bus(result_bus_vec);
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

    // method to request an instruction
    method ActionValue#(InstructionIssue) get if (rows[tail_r].ready);
        let i <- rows[tail_r].out();
        Bit#(entries) dummy = 0;
        tail_r <= rollover_add(dummy, tail_r, 1);

        `ifdef LOG_PIPELINE
            $fdisplay(out_log, "%d DISPATCH %x %d %d", clk_ctr, i.pc, i.tag, i.epoch);
            $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, i.log_id, 0, "S");
        `endif

        return i;
    endmethod

    // return execution unit tag
    method ExecUnitTag unit_type = eut;

    // input result bus
    method Action result_bus(Vector#(NUM_FU, Maybe#(ResultLoopback)) bus_in) = result_bus_vec._write(bus_in);

    // insert instructions
    interface ReservationStationPutIFC in;
        interface Put instruction;
            method Action put(InstructionIssue inst);
                if (valueOf(RS_LATCH_INPUT) == 0) begin
                    rows[head_r].in(inst);
                    Bit#(entries) dummy = 0;
                    head_r <= rollover_add(dummy, head_r, 1);
                end else begin
                    inst_in_f.enq(inst);
                end
                dbg_print(RS, $format("got inst: ", fshow(inst)));
            endmethod
        endinterface
        method Bool can_insert;
            Bit#(entries) dummy = 0;
            Integer advance_head = fromInteger(valueOf(RS_LATCH_INPUT)) + fromInteger(valueOf(SPLIT_ISSUE_STAGE));
            return  !rows[rollover_add(dummy, head_r, fromInteger(advance_head))].full;
        endmethod
    endinterface
endmodule


endpackage