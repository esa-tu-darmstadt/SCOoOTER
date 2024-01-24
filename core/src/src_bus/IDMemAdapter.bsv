package IDMemAdapter;
import Dave::*;
import Types::*;
import BlueAXI::*;
import Vector::*;
import ClientServer::*;
import Interfaces::*;
import MemoryDecoder::*;
import CLINT::*;
import FIFO::*;
import SpecialFIFOs::*;
import GetPut::*;
import RVController::*;
import CWire::*;
import PLIC::*;


interface MemBusIFC;

    //outgoing simple imem_rd iface
    interface Client#(Tuple2#(UInt#(XLEN), Bit#(TLog#(NUM_CPU))), Tuple2#(Bit#(TMul#(XLEN, IFUINST)), Bit#(TLog#(NUM_CPU)))) imem_r;

    //outgoing simple dmem ifaces
    interface Client#(Tuple2#(UInt#(TLog#(SIZE_DMEM)), Bit#(TAdd#(TLog#(NUM_CPU), 1))), Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) dmem_r;
    interface Client#(Tuple4#(UInt#(TLog#(SIZE_DMEM)), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))), Bit#(TAdd#(TLog#(NUM_CPU), 1))) dmem_w;

    //periphery/test signals
    (* always_ready, always_enabled *)
    method Action sw_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif

    method Bit#(XLEN) retval;
    method Bool done; 
endinterface

module mkMemCon#(FIFO#(Tuple2#(UInt#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) r_rq, FIFO#(Tuple4#(UInt#(XLEN), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) w_rq, MemMappedIFC#(a) dev, DaveIFC core, UInt#(32) base_addr, UInt#(32) addr_space, Reg#(Bool) sched_rd, Reg#(Bool) sched_wr)(Empty) provisos (
    Add#(a__, a, 32)
);

    rule rd_request if (decodeAddressRange(tpl_1(r_rq.first), base_addr, base_addr+addr_space));
        r_rq.deq();
        dev.mem_r.request.put(tuple2(truncate(tpl_1(r_rq.first)), tpl_2(r_rq.first)));
    endrule

    rule rd_response if (sched_rd);
        let r <- dev.mem_r.response.get();
        core.dmem_r.response.put(r);
        sched_rd <= False;
    endrule

    rule wr_request if (decodeAddressRange(tpl_1(w_rq.first), base_addr, base_addr+addr_space));
        w_rq.deq();
        dev.mem_w.request.put(tuple4(truncate(tpl_1(w_rq.first)), tpl_2(w_rq.first), tpl_3(w_rq.first), tpl_4(w_rq.first)));
    endrule

    rule wr_response if (sched_wr);
        let r <- dev.mem_w.response.get();
        core.dmem_w.response.put(r);
        sched_wr <= False;
    endrule

endmodule

(*synthesize*)
module mkIDMemAdapter(MemBusIFC) provisos (
    Div#(SIZE_DMEM, 4, dmem_word_num_t),
    Log#(dmem_word_num_t, dmem_addr_len_t)
);

    // instantiate core
    let core <- mkDave();
    
    /////////////////////
    // dmem bus and periphery

    // scheduling via revertingVirtualRegs
    Ehr#(4, Bool) sched_helper_rd <- mkCWire(True);
    Ehr#(4, Bool) sched_helper_wr <- mkCWire(True);

    // gather requests
    FIFO#(Tuple2#(UInt#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1))))                      dmem_r_rq <- mkPipelineFIFO();
    FIFO#(Tuple4#(UInt#(XLEN), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) dmem_w_rq <- mkPipelineFIFO();

    // get requests
    rule connect_dmem_rd;
        let rq <- core.dmem_r.request.get();
        dmem_r_rq.enq(rq);
    endrule
    rule connect_dmem_wr;
        let rq <- core.dmem_w.request.get();
        dmem_w_rq.enq(rq);
    endrule

    //// connect_periphery

    // CLINT
    let clint <- mkCLINT();
    let con_clint <- mkMemCon(dmem_r_rq, dmem_w_rq, clint.memory_bus, core, 32'h40000000, 32'h1000, sched_helper_rd[1], sched_helper_wr[1]);
    rule set_int_flags_timer;
        core.timer_int(unpack(pack(clint.timer_interrupts())));
    endrule

    //PLIC
    PLICIFC#(4, 8) plic <- mkPLIC();
    let con_plic <- mkMemCon(dmem_r_rq, dmem_w_rq, plic.memory_bus, core, 32'h50000000, 32'h400000, sched_helper_rd[2], sched_helper_wr[2]);
    rule set_plic_int_in;
        plic.interrupts_in(unpack(3));
    endrule
    rule set_int_flags_ext;
        core.ext_int(unpack(pack(plic.ext_interrupts_out())));
    endrule

    //RVController
    let rvcontroller <- mkRVController();
    let con_rvcontroller <- mkMemCon(dmem_r_rq, dmem_w_rq, rvcontroller.memory_bus, core, 32'h11000000, 32'h10000, sched_helper_rd[3], sched_helper_wr[3]);
    method Bit#(XLEN) retval = rvcontroller.retval();
    method Bool done = rvcontroller.done();

    // dmem
    interface Client dmem_r;
        interface Get request;
            // if condition checks whether the address is in dmem range
            method ActionValue#(Tuple2#(UInt#(TLog#(SIZE_DMEM)), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get() if (decodeAddressRange(tpl_1(dmem_r_rq.first), fromInteger(valueOf(BASE_DMEM)), fromInteger(valueOf(BASE_DMEM)+valueOf(SIZE_DMEM))));
                dmem_r_rq.deq();
                let r = dmem_r_rq.first();
                return tuple2(truncate(tpl_1(r)), tpl_2(r)); 
            endmethod
        endinterface
        interface Put response;
            // if condition checks whether the address is in dmem range
            method Action put(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1))) r) if (sched_helper_rd[0]);
                 core.dmem_r.response.put(r);
                 sched_helper_rd[0] <= False;
            endmethod
        endinterface
    endinterface
    interface Client dmem_w;
        interface Get request;
            // if condition checks whether the address is in dmem range
            method ActionValue#(Tuple4#(UInt#(TLog#(SIZE_DMEM)), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get() if (decodeAddressRange(tpl_1(dmem_w_rq.first), fromInteger(valueOf(BASE_DMEM)), fromInteger(valueOf(BASE_DMEM)+valueOf(SIZE_DMEM))));
                dmem_w_rq.deq();
                let r = dmem_w_rq.first();
                return tuple4(truncate(tpl_1(r)), tpl_2(r), tpl_3(r), tpl_4(r)); 
            endmethod
        endinterface
        interface Put response;
            // if condition checks whether the address is in dmem range
            method Action put(Bit#(TAdd#(TLog#(NUM_CPU), 1)) r)  if (sched_helper_wr[0]);
                 core.dmem_w.response.put(r);
                 sched_helper_wr[0] <= False;
            endmethod
        endinterface
    endinterface

    //////////////////////
    // External signals

    // imem does not need any memory area separation
    interface imem_r = core.imem_r;

    // forward periphery signals
    method Action sw_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in) = core.sw_int(in);

    // export branch prediction performance tracking
    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br = core.correct_pred_br;
        method UInt#(XLEN) wrong_pred_br = core.wrong_pred_br;
        method UInt#(XLEN) correct_pred_j = core.correct_pred_j;
        method UInt#(XLEN) wrong_pred_j = core.wrong_pred_j;
    `endif

endmodule





endpackage