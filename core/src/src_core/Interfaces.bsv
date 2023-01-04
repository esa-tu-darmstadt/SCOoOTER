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
interface IFU#(numeric type ifuwidth, numeric type buffercount);
    // AXI to IMEM
    interface AXI4_Master_Rd_Fab#(XLEN, ifuwidth, 0, 0) ifu_axi;
    // mispredict signal
    method Action redirect(Bit#(XLEN) newPC);
    // output iface to other units
    method MIMO::LUInt#(buffercount) count;
    method Action deq(MIMO::LUInt#(ISSUEWIDTH) amount);
    method Vector#(ISSUEWIDTH, InstructionPredecode) first;
endinterface

// decode and issue unit interface
interface DecodeIFC;
    method Action put(Vector#(ISSUEWIDTH, InstructionPredecode) instructions, MIMO::LUInt#(ISSUEWIDTH) amount);
    method MIMO::LUInt#(buffercount) count;
    method Action deq(MIMO::LUInt#(ISSUEWIDTH) amount);
    method Vector#(ISSUEWIDTH, InstructionPredecode) first;
    method Action redirect();
endinterface

interface DecAndIssueIFC;
    method Action put(Vector#(ISSUEWIDTH, InstructionPredecode) instructions, MIMO::LUInt#(ISSUEWIDTH) amount);
    (* always_ready, always_enabled *)
    method MIMO::LUInt#(ISSUEWIDTH) remove;
    method Bit#(XLEN) redirect_pc;
endinterface

interface ReservationStationIFC#(numeric type addrwidth, numeric type entries);
    method ActionValue#(Instruction) get;
    method UInt#(addrwidth) free;
    method List#(OpCode) supported_opc;
    method ExecUnitTag unit_type;
    method Action put(Vector#(ISSUEWIDTH, Instruction) inst, MIMO::LUInt#(ISSUEWIDTH) count);
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
endinterface

interface CommitIFC;
    method ActionValue#(UInt#(TLog#(TAdd#(ISSUEWIDTH,1)))) consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) count);
    method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
endinterface

interface RegFileIFC;
    //write of architectural registers from commit stage
    method Action write(Vector#(ISSUEWIDTH, Maybe#(RegWrite)) requests);
    //output of current arch registers, used in mispredict
    method Vector#(31, Bit#(XLEN)) values();
endinterface

interface RegFileEvoIFC;
    //set the correct tag corresponding to a register
    method Action set_tags(Vector#(ISSUEWIDTH, RegReservation) reservations, UInt#(TLog#(TAdd#(1, ISSUEWIDTH))) num);
    //read 2 regs per instruction
    method Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) read_regs(Vector#(TMul#(2, ISSUEWIDTH), RADDR) registers);
    //input the architectural registers post-commit
    (* always_ready, always_enabled *)
    method Action committed_state(Vector#(31, Bit#(XLEN)) regs);
    //inform about misprediction
    method Action flush();
endinterface

endpackage