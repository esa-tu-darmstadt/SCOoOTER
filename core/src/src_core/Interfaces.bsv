package Interfaces;

import BlueAXI :: *;
import Types :: *;

// Toplevel interface to external world
interface Top;
    (* prefix= "axi_master_ifu" *)
    interface AXI4_Master_Rd_Fab#(XLEN, IFUWIDTH, 0, 0) ifu_axi;
endinterface

// Instruction fetch unit iface
interface IFU;
    interface AXI4_Master_Rd_Fab#(XLEN, IFUWIDTH, 0, 0) ifu_axi;
    method Action redirect(Bit#(XLEN) newPC);
endinterface

endpackage