package AxiLiteAdapter;

import BlueAXI::*;
import Types::*;
import Interfaces::*;
import GetPut::*;
import ClientServer::*;
import FIFO::*;

/*


AxiAdapter adapts from the custom memory bus to AXI4 lite.
IDs are stored internally in a FIFO since BlueAXIs AXI4 Lite has no ID field.


*/


interface AxiLiteAdapterIFC#(numeric type aw);
    // internal memory iface
    // get requests from CPU side
    interface MemMappedIFC#(aw) memory_bus;
    // AXI interfaces
    // pass requests on to external devices
    // look at the AXI4 specification for a detailed explaination of the AXI4 Bus
    interface AXI4_Lite_Master_Rd_Fab#(aw, XLEN) rd;
    interface AXI4_Lite_Master_Wr_Fab#(aw, XLEN) wr;
endinterface

module mkAxiLiteAdapter(AxiLiteAdapterIFC#(aw)) provisos (
    Log#(NUM_CPU, cpu_idx_t),         // id width to track CPUs
                                      // we take the LOG of the CPU amount to get a bit width with one state per CPU
    Add#(1, cpu_idx_t, amo_cpu_idx_t) // add a bit to CPU id to encode AMOs or normal request
);

    // AXI4 Lite instances
    AXI4_Lite_Master_Rd#(aw, XLEN) rd_inst <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(aw, XLEN) wr_inst <- mkAXI4_Lite_Master_Wr(1);

    // FIFOs for ID storage
    // the ID of a request has to be returned with the response
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_r_fifo <- mkSizedFIFO(2);
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_w_fifo <- mkSizedFIFO(2);

    // connect the BlueAXI instances to the interface of this module
    interface AXI4_Lite_Master_Rd_Fab rd = rd_inst.fab;
    interface AXI4_Lite_Master_Wr_Fab wr = wr_inst.fab;

    // reading registers
    interface MemMappedIFC memory_bus;
        interface Server mem_r;
            interface Put request;
                method Action put(Tuple2#(UInt#(aw), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    // adapt custom memory bus request to AXI
                    AXI4_Lite_Read_Rq_Pkg#(aw) rq;
                    rq.addr = pack(tpl_1(req));
                    rq.prot = UNPRIV_SECURE_DATA;
                    rd_inst.request.put(rq);
                    // save request ID
                    inflight_ids_r_fifo.enq(tpl_2(req));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get();
                    // adapt AXI response to custom bus
                    let rs <- rd_inst.response.get();
                    inflight_ids_r_fifo.deq();
                    return tuple2(rs.data, inflight_ids_r_fifo.first());
                endmethod
            endinterface
        endinterface

        // writing registers
        interface Server mem_w;
            interface Put request;
                method Action put(Tuple4#(UInt#(aw), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    // save ID
                    inflight_ids_w_fifo.enq(tpl_4(req));

                    // Assemble AXI request
                    AXI4_Lite_Write_Rq_Pkg#(aw, XLEN) rq;
                    rq.addr = pack(tpl_1(req));
                    rq.data = tpl_2(req);
                    rq.strb = tpl_3(req);
                    rq.prot = UNPRIV_SECURE_DATA;

                    wr_inst.request.put(rq);
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) get();
                    // return AXI response to custom bus
                    let rs <- wr_inst.response.get();
                    inflight_ids_w_fifo.deq();
                    return inflight_ids_w_fifo.first();
                endmethod
            endinterface
        endinterface
    endinterface

endmodule

endpackage