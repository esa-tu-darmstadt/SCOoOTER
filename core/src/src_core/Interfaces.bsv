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
interface DecAndIssueIFC;
    method Action put(Vector#(ISSUEWIDTH, InstructionPredecode) instructions, MIMO::LUInt#(ISSUEWIDTH) amount);
    method MIMO::LUInt#(ISSUEWIDTH) remove;
    method Bit#(XLEN) redirect_pc;
endinterface

// decode and issue unit interface
interface ReservationStationIFC#(numeric type addrwidth, numeric type entries);
    method ActionValue#(Instruction) get;
    method UInt#(addrwidth) free;
    method List#(OpCode) supported_opc;
    method Action put(Vector#(ISSUEWIDTH, Instruction) inst, MIMO::LUInt#(ISSUEWIDTH) count);
endinterface

endpackage