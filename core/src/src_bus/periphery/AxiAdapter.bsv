package AxiAdapter;

import BlueAXI::*;
import Types::*;
import Interfaces::*;
import GetPut::*;
import ClientServer::*;

interface AxiAdapterIFC#(numeric type aw);
    interface MemMappedIFC#(aw) memory_bus;
    interface AXI4_Master_Rd_Fab#(aw, XLEN, TAdd#(TLog#(NUM_CPU), 1), 0) rd;
    interface AXI4_Master_Wr_Fab#(aw, XLEN, TAdd#(TLog#(NUM_CPU), 1), 0) wr;
endinterface

module mkAxiAdapter(AxiAdapterIFC#(aw)) provisos (
    Mul#(NUM_HARTS, 2, num_mtimecmp),
    Log#(NUM_CPU, cpu_idx_t),
    Add#(1, cpu_idx_t, amo_cpu_idx_t)
);

    AXI4_Master_Rd#(aw, XLEN, amo_cpu_idx_t, 0) rd_inst <- mkAXI4_Master_Rd(1, 1, False);
    AXI4_Master_Wr#(aw, XLEN, amo_cpu_idx_t, 0) wr_inst <- mkAXI4_Master_Wr(1, 1, 1, False);

    interface AXI4_Master_Rd_Fab rd = rd_inst.fab;
    interface AXI4_Master_Wr_Fab wr = wr_inst.fab;

    // reading registers
    interface MemMappedIFC memory_bus;
        interface Server mem_r;
            interface Put request;
                method Action put(Tuple2#(UInt#(aw), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    AXI4_Read_Rq#(aw, amo_cpu_idx_t, 0) rq = defaultValue;
                    rq.id = tpl_2(req);
                    rq.addr = pack(tpl_1(req));
                    rd_inst.request.put(rq);
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get();
                    let rs <- rd_inst.response.get();
                    return tuple2(rs.data, rs.id);
                endmethod
            endinterface
        endinterface

        // writing registers
        interface Server mem_w;
            interface Put request;
                method Action put(Tuple4#(UInt#(aw), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    AXI4_Write_Rq_Addr#(aw, amo_cpu_idx_t, 0) rq_a = defaultValue;
                    AXI4_Write_Rq_Data#(XLEN, 0) rq_d = defaultValue;

                    rq_a.id = tpl_4(req);
                    rq_a.addr = pack(tpl_1(req));
                    rq_d.data = tpl_2(req);
                    rq_d.strb = tpl_3(req);

                    wr_inst.request_addr.put(rq_a);
                    wr_inst.request_data.put(rq_d);
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) get();
                    let rs <- wr_inst.response.get();
                    return rs.id;
                endmethod
            endinterface
        endinterface
    endinterface

endmodule

endpackage