package IDMemAdapter;
import Dave::*;
import Types::*;
import BlueAXI::*;
import Vector::*;
import ClientServer::*;
import Interfaces::*;
import MemoryDecoder::*;

interface MemBusIFC;

    //outgoing simple imem_rd iface
    interface Client#(Tuple2#(UInt#(XLEN), Bit#(TLog#(NUM_CPU))), Tuple2#(Bit#(TMul#(XLEN, IFUINST)), Bit#(TLog#(NUM_CPU)))) imem_r;

    //outgoing simple dmem ifaces

    //outgoing axi periphery iface
    (* prefix= "axi_master_data" *)
    interface AXI4_Master_Rd_Fab#(XLEN, XLEN, TAdd#(1, TLog#(NUM_CPU)), 0) dmem_axi_r;
    (* prefix= "axi_master_data" *)
    interface AXI4_Master_Wr_Fab#(XLEN, XLEN, TAdd#(1, TLog#(NUM_CPU)), 0) dmem_axi_w;

    //periphery/test signals
    (* always_ready, always_enabled *)
    method Action sw_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in);
    (* always_ready, always_enabled *)
    method Action timer_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in);
    (* always_ready, always_enabled *)
    method Action ext_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif
endinterface


module mkIDMemAdapter(MemBusIFC);

    let core <- mkDave();

    interface imem_r = core.imem_r;
    interface dmem_axi_r = core.dmem_axi_r;
    interface dmem_axi_w = core.dmem_axi_w;

    // forward periphery signals
    method Action sw_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in) = core.sw_int(in);
    method Action timer_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in) = core.timer_int(in);
    method Action ext_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in) = core.ext_int(in);

    // export branch prediction performance tracking
    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br = core.correct_pred_br;
        method UInt#(XLEN) wrong_pred_br = core.wrong_pred_br;
        method UInt#(XLEN) correct_pred_j = core.correct_pred_j;
        method UInt#(XLEN) wrong_pred_j = core.wrong_pred_j;
    `endif

endmodule





endpackage