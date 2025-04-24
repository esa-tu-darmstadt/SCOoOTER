package ReorderBuffer;

/*
  The REORDER BUFFER stores instructions in order.
  It sniffs the result bus and marks instructions as complete.
  Complete instructions at the tail can be dequeued in programm
  order. New instructions enter at the head.

  The ROB is basically a ring buffer.

  The ROB also provides signals to CSR and LSU to guard their
  reordering.
*/

import Vector::*;
import Inst_Types::*;
import Types::*;
import Interfaces::*;
import FIFO::*;
import SpecialFIFOs::*;
import Debug::*;
import TestFunctions::*;
import GetPut::*;
import ClientServer::*;
import BuildVector::*;
import Ehr::*;
import FIFOF::*;
import BUtils::*;

// interface for a single ROB entry
interface RobRowIFC;
    (* always_ready, always_enabled *)
    method Bool empty(); // is empty
    (* always_ready, always_enabled *)
    method Bool ready(); // instruction is ready and can be dequeued

    // FIFO-like interface
    method Action put(RobEntry re);
    method RobEntry first();
    method Action deq();

    // connection to result bus for result reading
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);
endinterface

// single entry inside the ROB
// the entry can get an instruction and a ready instruction may be dequeued
// an instruction is ready, once the result is known
// an entry has a fixed ID and matches the result bus for that fixed ID
module mkReorderBufferRow#(Integer base_id, Integer id_inc, Integer pos)(RobRowIFC);

    // fixed ID of this entry
    Integer rob_id = base_id + id_inc * pos;

    // instruction entry
    Reg#(RobEntry) entry_r <- mkRegU; // instruction data
    Reg#(ResultOrExcept) result_r <- mkRegU; // result/exception if already produced
    Reg#(Maybe#(Bit#(PCLEN))) next_pc_r <- mkRegU; // next (predicted) PC
    `ifdef RVFI
        Reg#(UInt#(XLEN)) mem_addr_r <- mkRegU; // accessed memory address for tracing
    `endif

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

    // status flags
    Reg#(Bool) occupied_r[2] <- mkCReg(2, False);
    Reg#(Bool) ready_r[2] <- mkCReg(2, False);

    // needed for BSV schedule
    PulseWire schedulingFix <- mkPulseWire();

    // result bus wire
    Wire#(Vector#(NUM_FU, Maybe#(Result))) result_bus_w <- mkBypassWire();

    // helper function to test for found result
    function Bool fits_id(Maybe#(Result) result) = (isValid(result) && result.Valid.tag == fromInteger(rob_id));

    // check result bus for fitting result
    rule consume_result_bus;
        let res_bus = result_bus_w;

        // use helper function
        let fitting_result = find(fits_id, res_bus);

        // if found
        if (fitting_result matches tagged Valid .v) begin
            ready_r[0] <= True; // set entry as ready

            result_r <= v.Valid.result;

            `ifdef RVFI // expose memory address via RVFI
                mem_addr_r <= v.Valid.mem_addr;
            `endif

            // generate the next pc field from the result
            next_pc_r <= v.Valid.new_pc;

            // write info for pipeline viewer
            `ifdef LOG_PIPELINE
                $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, entry_r.log_id, 0, "E");
            `endif
        end
    endrule

    // store a new instruction
    method Action put(RobEntry re);
        entry_r <= re;
        occupied_r[1] <= True;
        ready_r[1] <= False;
        schedulingFix.send();

        dbg_print(ROB, $format("got: ", fshow(re)));

        // addertions
        if (occupied_r[1] == True) begin
            $display("Trying to enqueue into a full ROB cell. Abort.");
            $finish();
        end
    endmethod

    // get stored instruction
    method RobEntry first();
        let entry = entry_r;
        entry.next_pc = case (next_pc_r) matches
            tagged Valid .n : n;
            tagged Invalid  : (entry_r.pc+1);
        endcase;
        entry.result = result_r;
        `ifdef RVFI // for testing, expose memory address
            entry.mem_addr = mem_addr_r;
        `endif
        return entry;
    endmethod
    // dequeue stored instruction
    method Action deq() = occupied_r[0]._write(False);

    // get result bus
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus) = result_bus_w._write(res_bus);
    
    // report status
    method Bool empty() = !occupied_r[0];
    method Bool ready() = occupied_r[0] && ready_r[0];

endmodule


// A ROB bank is an assembly of multiple ROB rows. A ROB bank has a single enq and deq port.
interface RobBankIFC;

    (* always_ready, always_enabled *)
    method Bool ready_enq(); // enqueue in the current cycle is possible
    method Bool ready_enq_next(); // at least two slots are empty - needed if a pipeline stage is inserted (see Config)
    (* always_ready, always_enabled *)
    method Bool ready_deq(); // the next instruction is completed and can be dequeued

    method Action put(RobEntry re); // enqueue an instruction
    method RobEntry first(); // peek at the first entry
    method Action deq(); // dequeue the first entry

    // connect the result bus
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);

    // idx of next instruction to be dequeued
    method UInt#(TLog#(ROB_BANK_DEPTH)) current_tail_idx;
endinterface

module mkReorderBufferBank#(Integer base_id, Integer id_inc)(RobBankIFC) provisos (
    Log#(ROB_BANK_DEPTH, local_idx) // id width necessary for all slots
);

    Bit#(ROB_BANK_DEPTH) dummy = 0;

    // state, which entry is head and which one is tail
    // a ROB bank is organized as a ring buffer with the two pointers keeping track
    // of the start/end of the contents
    Reg#(UInt#(local_idx)) local_head <- mkReg(0);
    Reg#(UInt#(local_idx)) local_tail <- mkReg(0);

    // instantiate rows according to entry number
    Vector#(ROB_BANK_DEPTH, RobRowIFC) rows <- genWithM(mkReorderBufferRow(base_id, id_inc));

    // return correct ready and empty signals, depending on head
    method Bool ready_enq() = rows[local_head].empty();
    method Bool ready_enq_next() = rows[rollover_add(dummy, local_head, 1)].empty();
    method Bool ready_deq() = rows[local_tail].ready();

    // enqueue instruction
    method Action put(RobEntry re);
        rows[local_head].put(re);
        local_head <= rollover_add(dummy, local_head, 1); 
    endmethod

    // get current tail instruction
    method RobEntry first() = rows[local_tail].first();

    // dequeue instruction
    method Action deq();
        local_tail <= rollover_add(dummy, local_tail, 1);
        rows[local_tail].deq(); 
    endmethod

    // get result bus
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);
        for (Integer i = 0; i < valueOf(ROB_BANK_DEPTH); i=i+1)
            rows[i].result_bus(res_bus);
    endmethod

    // return current tail id
    method UInt#(TLog#(ROB_BANK_DEPTH)) current_tail_idx = local_tail;
endmodule

// full reorder buffer consisting of multiple banks
`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkReorderBufferNew(RobIFC) provisos (
    Log#(ISSUEWIDTH, issue_idx_t), // id width for issued instructions
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issue_amt_t) // data type width to signify number of instructions enqueued in this cycle
);


    // logging for Konata
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

    // needed as input for truncated add function
    // such that the ISSUEWIDTH is transported to the function
    // this variable is never actually used
    Bit#(ISSUEWIDTH) dummy = 0;

    // generate ROB banks and initialize each ROB row with its accompanying index
    Vector#(ISSUEWIDTH, RobBankIFC) robbank <- genWithM(flip(mkReorderBufferBank)(valueOf(ISSUEWIDTH)));

    // track which bank has next enq/deq operation
    Reg#(UInt#(issue_idx_t)) head_bank_r <- mkReg(0);
    Reg#(UInt#(issue_idx_t)) tail_bank_r <- mkReg(0);

    // helper functions to extract signals from a bank
    function Bool get_rdy_enq(RobBankIFC rb) = valueOf(ROB_BANK_DEPTH) > 1 ? rb.ready_enq_next() : rb.ready_enq(); // TODO: PARAMETRIZE
    function Bool get_rdy_deq(RobBankIFC rb) = rb.ready_deq();
    function RobEntry get_entry(RobBankIFC rb) = rb.first();

    // function needed for counting ready instructions
    function UInt#(issue_amt_t) fold_rdy_deq_amt(Bool in, UInt#(issue_amt_t) cnt) = unpack(pack(cnt + 1) & replicate_bit(pack(in)));

    // output buffering
    Reg#(UInt#(issue_amt_t)) amt_out_r <- (valueOf(ROB_LATCH_OUTPUT) == 1 ? mkReg(0) : mkBypassWire());
    Reg#(Vector#(ISSUEWIDTH, RobEntry)) out_r <- (valueOf(ROB_LATCH_OUTPUT) == 1 ? mkRegU : mkBypassWire());
    Reg#(UInt#(TLog#(ROBDEPTH))) tail_out_r <- (valueOf(ROB_LATCH_OUTPUT) == 1 ? mkReg(0) : mkBypassWire());

    // generate a combined ID for the next instruction to be dequeued
    rule fwd_tail;
        tail_out_r <= extend(tail_bank_r) + extend(robbank[tail_bank_r].current_tail_idx())*cExtend(fromInteger(valueOf(ISSUEWIDTH)));
    endrule

    // DExIE may stall SCOoOTER. Stall signal is connected here
    `ifdef DEXIE
        Wire#(Bool) dexie_stall_w <- mkBypassWire();
    `endif

    // dequeue ready instructions and provide them to the commit stage
    // calculates the number of instructions and advances the tail pointer accordingly
    rule calc_insts
        `ifdef DEXIE
            if (!dexie_stall_w) // stalled by DExIE if necessary
        `endif
    ;
        // calculate number of rob banks with a ready instruction from the current tail bank onwards
        let amt_current = foldr(fold_rdy_deq_amt, 0, rotateBy(map(get_rdy_deq, robbank), truncate(fromInteger(valueOf(ISSUEWIDTH)) - unpack({1'b0, pack(tail_bank_r)}))));
        // dequeue from the associated rob banks
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1)
            if (fromInteger(i) < amt_current)
                robbank[rollover_add(dummy, tail_bank_r, fromInteger(i))].deq();

        // advance the tail bank pointer
        tail_bank_r <= rollover_add(dummy, tail_bank_r, cExtend(amt_current));
        // forward to the commit stage
        amt_out_r <= amt_current;
        out_r <= rotateBy(map(get_entry, robbank), truncate(fromInteger(valueOf(ISSUEWIDTH)) - unpack({1'b0, pack(tail_bank_r)})));
    endrule

    // incoming instructions are buffered for one cycle to reduce the critical path
    // this rule inserts the buffered entries
    Reg#(Tuple2#(Vector#(ISSUEWIDTH, RobEntry), Bit#(ISSUEWIDTH))) incoming_res <- valueOf(ROB_BANK_DEPTH) > 1 ? mkReg(unpack(0)) : mkBypassWire();
    rule insert;
        let data = tpl_1(incoming_res);
        let mask = tpl_2(incoming_res);
        let enq_data = rotateBy(data, head_bank_r); // align new entries to correctly sequence them into the banks

        // enqueue data into the banks
        Vector#(ISSUEWIDTH, Bool) enq_fire = rotateBy(unpack(mask), head_bank_r);
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            if (enq_fire[i]) robbank[i].put(enq_data[i]);
        end

        // advance head pointer
        head_bank_r <= rollover_add(dummy, head_bank_r, cExtend(Vector::countElem(True, unpack(mask))));
    endrule

    // count how many instructions at the ROB head are ready
    method UInt#(issue_amt_t) available = amt_out_r;

    // count how many instructions could be enqueued
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) free = extend(countElem(True, map(get_rdy_enq, robbank)));

    // inform execution units of next committed instruction
    method UInt#(TLog#(ROBDEPTH)) current_tail_idx = tail_out_r;

    // get instructions from issue
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, Bit#(ISSUEWIDTH) mask);
        incoming_res <= tuple2(data, mask);
    endmethod

    // read the head entries - instructions towards commit stage
    method ActionValue#(Vector#(ISSUEWIDTH, RobEntry)) get();
        return out_r;
    endmethod

    // connect the result bus to the ROB banks
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1)
            robbank[i].result_bus(res_bus);
    endmethod

    // information for the DExIE control flow integrity engine
    `ifdef DEXIE
        method Action dexie_stall(Bool stall) = dexie_stall_w._write(stall);
    `endif
endmodule



endpackage
