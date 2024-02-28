package AxiLiteAdapter;

import BlueAXI::*;
import Types::*;
import Interfaces::*;
import GetPut::*;
import ClientServer::*;
import FIFO::*;

interface AxiLiteAdapterIFC#(numeric type aw);
    interface MemMappedIFC#(aw) memory_bus;
    interface AXI4_Lite_Master_Rd_Fab#(aw, XLEN) rd;
    interface AXI4_Lite_Master_Wr_Fab#(aw, XLEN) wr;
endinterface

module mkAxiLiteAdapter(AxiLiteAdapterIFC#(aw)) provisos (
    Mul#(NUM_HARTS, 2, num_mtimecmp),
    Log#(NUM_CPU, cpu_idx_t),
    Add#(1, cpu_idx_t, amo_cpu_idx_t)
);

    AXI4_Lite_Master_Rd#(aw, XLEN) rd_inst <- mkAXI4_Lite_Master_Rd(1);
    AXI4_Lite_Master_Wr#(aw, XLEN) wr_inst <- mkAXI4_Lite_Master_Wr(1);

    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_r_fifo <- mkSizedFIFO(2);
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_w_fifo <- mkSizedFIFO(2);

    interface AXI4_Lite_Master_Rd_Fab rd = rd_inst.fab;
    interface AXI4_Lite_Master_Wr_Fab wr = wr_inst.fab;

    // reading registers
    interface MemMappedIFC memory_bus;
        interface Server mem_r;
            interface Put request;
                method Action put(Tuple2#(UInt#(aw), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    AXI4_Lite_Read_Rq_Pkg#(aw) rq;
                    rq.addr = pack(tpl_1(req));
                    rq.prot = UNPRIV_SECURE_DATA;
                    rd_inst.request.put(rq);

                    inflight_ids_r_fifo.enq(tpl_2(req));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get();
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
                    AXI4_Lite_Write_Rq_Pkg#(aw, XLEN) rq;

                    inflight_ids_w_fifo.enq(tpl_4(req));
                    rq.addr = pack(tpl_1(req));
                    rq.data = tpl_2(req);
                    rq.strb = tpl_3(req);
                    rq.prot = UNPRIV_SECURE_DATA;

                    wr_inst.request.put(rq);
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) get();
                    let rs <- wr_inst.response.get();
                    inflight_ids_w_fifo.deq();
                    return inflight_ids_w_fifo.first();
                endmethod
            endinterface
        endinterface
    endinterface

endmodule

endpackage