package ReorderBufferNew;

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
import WireFIFO::*;
import BUtils::*;

interface RobRowIFC;

    (* always_ready, always_enabled *)
    method Bool empty();
    (* always_ready, always_enabled *)
    method Bool ready();

    method Action put(RobEntry re);
    method RobEntry first();
    method Action deq();

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);
endinterface

// single entry inside the ROB
// the entry can get an instruction and a ready instruction may be dequeued
// an instruction is ready, once the result is known
// an entry has a fixed ID and matches the result bus for that fixed ID
module mkReorderBufferRow#(Integer base_id, Integer id_inc, Integer pos)(RobRowIFC);

    // fixed ID of this entry
    Integer rob_id = base_id + id_inc * pos;

    // real instruction entry
    Reg#(RobEntry) entry_r <- mkRegU;
    Reg#(ResultOrExcept) result_r <- mkRegU;
    Reg#(Bit#(PCLEN)) next_pc_r <- mkRegU;
    `ifdef RVFI
        Reg#(UInt#(XLEN)) mem_addr_r <- mkRegU;
    `endif

    // status flags
    Reg#(Bool) occupied_r[2] <- mkCReg(2, False);
    Reg#(Bool) ready_r[2] <- mkCReg(2, False);

    // needed for schedule
    PulseWire schedulingFix <- mkPulseWire();
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

            `ifdef RVFI // for testing, expose memory address
                mem_addr_r <= v.Valid.mem_addr;
            `endif

            // generate the next pc field from the result
            next_pc_r <= case (v.Valid.new_pc) matches
                tagged Valid .n : truncateLSB(n);
                tagged Invalid  : truncateLSB(entry_r.pc+1);
            endcase;

            // write info for pipeline viewer
            `ifdef LOG_PIPELINE
                $fdisplay(out_log, "%d COMPLETE %x %d %d", clk_ctr, entry_r.pc, i, entry_r.epoch);
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
    endmethod

    // get stored instruction
    method RobEntry first();
        let entry = entry_r;
        entry.next_pc = next_pc_r;
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


// A ROB bank is an assembly of multiple ROB entries. A ROB bank has a single enq and deq port.
interface RobBankIFC;

    (* always_ready, always_enabled *)
    method Bool ready_enq();
    (* always_ready, always_enabled *)
    method Bool ready_deq();

    method Action put(RobEntry re);
    method RobEntry first();
    method Action deq();

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);

    method UInt#(TLog#(ROB_BANK_DEPTH)) current_tail_idx;
endinterface

module mkReorderBufferBank#(Integer base_id, Integer id_inc)(RobBankIFC) provisos (
    Log#(ROB_BANK_DEPTH, local_idx)
);

    Bit#(ROB_BANK_DEPTH) dummy = 0;

    // state, which entry is head and which one is tail
    Reg#(UInt#(local_idx)) local_head <- mkReg(0);
    Reg#(UInt#(local_idx)) local_tail <- mkReg(0);

    // instantiate multiple rows
    Vector#(ROB_BANK_DEPTH, RobRowIFC) rows <- genWithM(mkReorderBufferRow(base_id, id_inc));

    // return correct ready and empty signals, depending on head
    method Bool ready_enq() = rows[local_head].empty();
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


`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkReorderBufferNew(RobIFC) provisos (
    Log#(ISSUEWIDTH, issue_idx_t),
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issue_amt_t)
);

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
    // this variable is never used
    Bit#(ISSUEWIDTH) dummy = 0;

    // generate ROB banks and initialize each ROB row with its accompanying index
    Vector#(ISSUEWIDTH, RobBankIFC) robbank <- genWithM(flip(mkReorderBufferBank)(valueOf(ISSUEWIDTH)));

    // track which bank has next enq/deq operation
    Reg#(UInt#(issue_idx_t)) head_bank_r <- mkReg(0);
    Reg#(UInt#(issue_idx_t)) tail_bank_r <- mkReg(0);

    // helper functions to extract signals from a bank
    function Bool get_rdy_enq(RobBankIFC rb) = rb.ready_enq();
    function Bool get_rdy_deq(RobBankIFC rb) = rb.ready_deq();
    function RobEntry get_entry(RobBankIFC rb) = rb.first();

    // function needed for counting ready instructions
    function UInt#(issue_amt_t) fold_rdy_deq_amt(Bool in, UInt#(issue_amt_t) cnt) = unpack(pack(cnt + 1) & replicate_bit(pack(in)));

    // output buffering
    Reg#(UInt#(issue_amt_t)) amt_out_r <- (valueOf(ROB_LATCH_OUTPUT) == 1 ? mkReg(0) : mkBypassWire());
    Reg#(Vector#(ISSUEWIDTH, RobEntry)) out_r <- (valueOf(ROB_LATCH_OUTPUT) == 1 ? mkRegU : mkBypassWire());
    
    rule calc_amt;
        amt_out_r <= foldr(fold_rdy_deq_amt, 0, rotateBy(map(get_rdy_deq, robbank), truncate(fromInteger(valueOf(ISSUEWIDTH)) - unpack({1'b0, pack(tail_bank_r)}))));
    endrule

    rule calc_insts;
        let amt_current = foldr(fold_rdy_deq_amt, 0, rotateBy(map(get_rdy_deq, robbank), truncate(fromInteger(valueOf(ISSUEWIDTH)) - unpack({1'b0, pack(tail_bank_r)}))));
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1)
            if (fromInteger(i) < amt_current)
                robbank[rollover_add(dummy, tail_bank_r, fromInteger(i))].deq();


        tail_bank_r <= rollover_add(dummy, tail_bank_r, cExtend(amt_current));
        out_r <= rotateBy(map(get_entry, robbank), truncate(fromInteger(valueOf(ISSUEWIDTH)) - unpack({1'b0, pack(tail_bank_r)})));
    endrule

    // count how many instructions at the ROB head are ready
    method UInt#(issue_amt_t) available = amt_out_r;

    // count how many instructions could be enqueued
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) free = extend(countElem(True, map(get_rdy_enq, robbank)));

    // inform execution units of next committed instruction
    method UInt#(TLog#(ROBDEPTH)) current_tail_idx = extend(tail_bank_r) + extend(robbank[tail_bank_r].current_tail_idx())*cExtend(fromInteger(valueOf(ISSUEWIDTH)));

    // get instructions from issue
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, UInt#(issue_amt_t) num);
        let enq_data = rotateBy(data, head_bank_r);

        function Bool should_fire(Integer i) = fromInteger(i) < num;
        Vector#(ISSUEWIDTH, Bool) enq_fire = rotateBy(genWith(should_fire), head_bank_r);

        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1)
            if (enq_fire[i]) robbank[i].put(enq_data[i]);


        head_bank_r <= rollover_add(dummy, head_bank_r, cExtend(num));
    endmethod

    method ActionValue#(Vector#(ISSUEWIDTH, RobEntry)) get();
        return out_r;
    endmethod

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1)
            robbank[i].result_bus(res_bus);
    endmethod
endmodule



endpackage
