package Interfaces;

import BlueAXI :: *;
import Types :: *;
import Inst_Types :: *;
import MIMO :: *;
import Vector :: *;
import List :: *;

// Toplevel interface to external world
interface Top#(numeric type ifuwidth);
    (* prefix= "axi_master_ifu" *)
    interface AXI4_Master_Rd_Fab#(XLEN, ifuwidth, 0, 0) ifu_axi;
endinterface

// Instruction fetch unit iface
interface IFU;
    // AXI to IMEM
    interface AXI4_Master_Rd_Fab#(XLEN, TMul#(XLEN, IFUINST), 0, 0) ifu_axi;
    // mispredict signal
    method Action redirect(Bit#(XLEN) newPC);
    // output iface to other units
    method MIMO::LUInt#(IFUINST) count;
    method Action deq();
    method Vector#(IFUINST, Tuple3#(Bit#(32), Bit#(32), UInt#(XLEN))) first();
endinterface

interface DecodeIFC;
    method Action put(MIMO::LUInt#(IFUINST) amount, Vector#(IFUINST, Bit#(XLEN)) instructions, Vector#(IFUINST, Bit#(XLEN)) pc, Vector#(IFUINST, UInt#(XLEN)) epochs);
    method MIMO::LUInt#(INST_WINDOW) count;
    method Action deq(MIMO::LUInt#(ISSUEWIDTH) amount);
    method Vector#(ISSUEWIDTH, Instruction) first;
endinterface

interface IssueIFC;
    method Action put(Vector#(ISSUEWIDTH, Instruction) instructions, MIMO::LUInt#(ISSUEWIDTH) amount);
    method MIMO::LUInt#(ISSUEWIDTH) remove;

    method Vector#(TMul#(2, ISSUEWIDTH), RADDR) request_addrs();
    method Action response_regs(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) response);
    method Tuple3#(Vector#(ISSUEWIDTH, RegReservation), Vector#(ISSUEWIDTH, UInt#(XLEN)), MIMO::LUInt#(ISSUEWIDTH)) request_tags;

    (* always_ready, always_enabled *)
    method Action rob_free(UInt#(TLog#(TAdd#(ROBDEPTH,1))) free);
    (* always_ready, always_enabled *)
    method Action rob_current_idx(UInt#(TLog#(ROBDEPTH)) idx);
    method Tuple2#(Vector#(ISSUEWIDTH, RobEntry), MIMO::LUInt#(ISSUEWIDTH)) get_reservation();

    method Action rs_ready(Vector#(NUM_RS, Bool) rdy);
    method Action rs_type(Vector#(NUM_RS, ExecUnitTag) in);

    method Vector#(NUM_RS, Maybe#(Instruction)) get_issue();

    method Tuple2#(Vector#(ISSUEWIDTH, Tuple3#(RADDR, UInt#(TLog#(ROBDEPTH)), UInt#(XLEN))), MIMO::LUInt#(ISSUEWIDTH)) set_tags();
endinterface

interface ReservationStationIFC#(numeric type entries);
    method ActionValue#(Instruction) get;
    (* always_ready, always_enabled *)
    method Bool free;
    (* always_ready, always_enabled *)
    method ExecUnitTag unit_type;
    method Action put(Instruction inst);
    (* always_ready, always_enabled *)
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);
endinterface

interface FunctionalUnitIFC;
    method Action put(Instruction inst);
    (* always_enabled *)
    method Maybe#(Result) get();
endinterface

interface RobIFC;
    method UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) available;
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) free;
    method UInt#(TLog#(ROBDEPTH)) current_idx;

    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, UInt#(TLog#(TAdd#(1, ISSUEWIDTH))) num);
    method Vector#(ISSUEWIDTH, RobEntry) get();
    method Action complete_instructions(UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) count);

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);
endinterface

interface CommitIFC;
    method ActionValue#(UInt#(TLog#(TAdd#(ISSUEWIDTH,1)))) consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) count);
    method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    method Bit#(XLEN) redirect_pc();
endinterface

interface RegFileIFC;
    //write of architectural registers from commit stage
    method Action write(Vector#(ISSUEWIDTH, Maybe#(RegWrite)) requests);
    //output of current arch registers, used in mispredict
    method Vector#(31, Bit#(XLEN)) values();
endinterface

interface RegFileEvoIFC;
    //set the correct tag corresponding to a register
    method Action set_tags(Vector#(ISSUEWIDTH, RegReservation) reservations, Vector#(ISSUEWIDTH, UInt#(XLEN)) epochs, UInt#(TLog#(TAdd#(1, ISSUEWIDTH))) num);
    //read 2 regs per instruction
    method Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) read_regs(Vector#(TMul#(2, ISSUEWIDTH), RADDR) registers);
    //input the architectural registers post-commit
    (* always_ready, always_enabled *)
    method Action committed_state(Vector#(31, Bit#(XLEN)) regs);
    //inform about misprediction
    method Action flush();
    (* always_ready, always_enabled *)
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);
endinterface

endpackage