package AxiAdapter;

/*


AxiAdapter adapts from the custom memory bus to AXI4 full.
IDs are passed through via the AXI4 bus.


*/

import BlueAXI::*;
import Types::*;
import Interfaces::*;
import GetPut::*;
import ClientServer::*;


interface AxiAdapterIFC#(numeric type aw);
    // internal memory iface
    interface MemMappedIFC#(aw) memory_bus;
    // AXI interfaces
    interface AXI4_Master_Rd_Fab#(aw, XLEN, TAdd#(TLog#(NUM_CPU), 1), 0) rd;
    interface AXI4_Master_Wr_Fab#(aw, XLEN, TAdd#(TLog#(NUM_CPU), 1), 0) wr;
endinterface

module mkAxiAdapter(AxiAdapterIFC#(aw)) provisos (
    Log#(NUM_CPU, cpu_idx_t),         // id width to track CPUs
    Add#(1, cpu_idx_t, amo_cpu_idx_t) // add a bit to CPU id to encode AMOs or normal request
);

    // AXI4 instances
    AXI4_Master_Rd#(aw, XLEN, amo_cpu_idx_t, 0) rd_inst <- mkAXI4_Master_Rd(1, 1, False);
    AXI4_Master_Wr#(aw, XLEN, amo_cpu_idx_t, 0) wr_inst <- mkAXI4_Master_Wr(1, 1, 1, False);

    // provide axi on toplevel interface
    interface AXI4_Master_Rd_Fab rd = rd_inst.fab;
    interface AXI4_Master_Wr_Fab wr = wr_inst.fab;

    // register read implementation
    interface MemMappedIFC memory_bus;
        interface Server mem_r;
            interface Put request;
                method Action put(Tuple2#(UInt#(aw), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    // adapt custom memory bus request to AXI
                    AXI4_Read_Rq#(aw, amo_cpu_idx_t, 0) rq = defaultValue;
                    rq.id = tpl_2(req);
                    rq.addr = pack(tpl_1(req));
                    rd_inst.request.put(rq);
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get();
                    // adapt AXI response to custom bus
                    let rs <- rd_inst.response.get();
                    return tuple2(rs.data, rs.id);
                endmethod
            endinterface
        endinterface

        // writing registers
        interface Server mem_w;
            interface Put request;
                method Action put(Tuple4#(UInt#(aw), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    // two requests are needed for AXI since addr and data are separate channels
                    AXI4_Write_Rq_Addr#(aw, amo_cpu_idx_t, 0) rq_a = defaultValue;
                    AXI4_Write_Rq_Data#(XLEN, 0) rq_d = defaultValue;

                    // populate request
                    rq_a.id = tpl_4(req);
                    rq_a.addr = pack(tpl_1(req));
                    rq_d.data = tpl_2(req);
                    rq_d.strb = tpl_3(req);

                    // send AXI request
                    wr_inst.request_addr.put(rq_a);
                    wr_inst.request_data.put(rq_d);
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) get();
                    // return AXI response to custom bus
                    let rs <- wr_inst.response.get();
                    return rs.id;
                endmethod
            endinterface
        endinterface
    endinterface

endmodule

endpackage