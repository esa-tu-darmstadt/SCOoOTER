package SCOoOTER_wrapper;
    import Dave::*;
    import Interfaces::*;

    import GetPut::*;
    import ClientServer::*;
    import Clocks::*;

    import FIFO::*;
    import SpecialFIFOs::*;
    import Vector::*;

    import Inst_Types::*;

    /*
    
    This is a wrapper around SCOoOTER to simplify the interface for ASIC integration.
    
    */

    interface WrappedCPUIfc;
        // instruction and data memory interfaces
        // currently, ASIC synthesis is only possible with 32 bit bus widths, so only single-issue
        interface Client#(UInt#(32), Bit#(32)) imem_r;
        interface Client#(UInt#(32), Bit#(32)) dmem_r;
        interface Client#(Tuple3#(UInt#(32), Bit#(32), Bit#(4)), Bit#(0)) dmem_w;

        // interrupt signals
        (* always_ready, always_enabled *)
        method Action interrupts(Bool sw, Bool timer, Bool ext);
    endinterface

    module mkSCOoOTERWrapped(WrappedCPUIfc);

        // instantiate scoooter
        DaveIFC dave <- mkDave();

        // stateful elements for rdwr bus IDs
        // which must be returned with the response
        FIFO#(Bit#(1)) inflight_r_ids_mem <- mkSizedFIFO(1);
        FIFO#(Bit#(1)) inflight_w_ids_mem <- mkSizedFIFO(1);

        // IMEM read
        interface Client imem_r;
            interface Get request;
                method ActionValue#(UInt#(32)) get();
                    let r <- dave.imem_r.request.get();
                    return tpl_1(r);
                endmethod
            endinterface
            interface Put response;
                method Action put(Bit#(32) in);
                    dave.imem_r.response.put(tuple2(in,0));
                endmethod
            endinterface
        endinterface

        // DMEM read
        interface Client dmem_r;
            interface Get request;
                method ActionValue#(UInt#(32)) get();
                    let r <- dave.dmem_r.request.get();
                    inflight_r_ids_mem.enq(tpl_2(r));
                    return tpl_1(r);
                endmethod
            endinterface
            interface Put response;
                method Action put(Bit#(32) in);
                    inflight_r_ids_mem.deq();
                    dave.dmem_r.response.put(tuple2(in,inflight_r_ids_mem.first()));
                endmethod
            endinterface
        endinterface

        // DMEM write
        interface Client dmem_w;
            interface Get request;
                method ActionValue#(Tuple3#(UInt#(32), Bit#(32), Bit#(4))) get();
                    let r <- dave.dmem_w.request.get();
                    inflight_w_ids_mem.enq(tpl_4(r));
                    return tuple3(tpl_1(r), tpl_2(r), tpl_3(r));
                endmethod
            endinterface
            interface Put response;
                method Action put(Bit#(0) in);
                    inflight_w_ids_mem.deq();
                    dave.dmem_w.response.put(inflight_w_ids_mem.first());
                endmethod
            endinterface
        endinterface

        //irq
        method Action interrupts(Bool sw, Bool timer, Bool ext);
            dave.sw_int(replicate(replicate(sw)));
            dave.timer_int(replicate(replicate(timer)));
            dave.ext_int(replicate(replicate(ext)));
        endmethod

    endmodule

endpackage