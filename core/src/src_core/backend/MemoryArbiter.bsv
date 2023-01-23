package MemoryArbiter;

import BlueAXI::*;
import Types::*;
import Inst_Types::*;
import GetPut::*;
import ClientServer::*;
import Interfaces::*;
import FIFOF::*;
import SpecialFIFOs::*;

module mkMemoryArbiter(MemoryArbiterIFC);

    //AXI modules
    AXI4_Master_Rd#(XLEN, XLEN, 0, 0) axi_rd <- mkAXI4_Master_Rd(0, 0, False);
    AXI4_Master_Wr#(XLEN, XLEN, 0, 0) axi_wr <- mkAXI4_Master_Wr(0, 0, 0, False);

    PulseWire serialize_r_w <- mkPulseWire();

    // axi to data memory
    interface axi_r = axi_rd.fab();
    interface axi_w  = axi_wr.fab();

    // normal reads/writes
    interface Server write;
        interface Put request;
            method Action put(MemWr write);
                serialize_r_w.send();
                //$display("set");

                axi_wr.request_addr.put(AXI4_Write_Rq_Addr {
                    id: 0,
                    addr: pack(write.mem_addr),
                    burst_length: 0,
                    burst_size: B1,
                    burst_type: defaultValue,
                    lock: defaultValue,
                    cache: defaultValue,
                    prot: defaultValue,
                    qos: 0,
                    region: 0,
                    user: 0
                });
                axi_wr.request_data.put(AXI4_Write_Rq_Data {
                    data: write.data,
                    strb: write.store_mask,
                    last: True,
                    user: 0
                });
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(void) get();
                let r <- axi_wr.response.get();
                return ?;
            endmethod
        endinterface
    endinterface

    interface Server read;
        interface Put request;
            method Action put(Bit#(XLEN) req) if (!serialize_r_w);
                axi_rd.request.put(AXI4_Read_Rq {
                    id: 0,
                    addr: req,
                    burst_length: 0,
                    burst_size: B4,
                    burst_type: INCR,
                    lock: NORMAL,
                    cache: NORMAL_NON_CACHEABLE_NON_BUFFERABLE,
                    prot: UNPRIV_SECURE_DATA,
                    qos: 0,
                    region: 0,
                    user: 0
                });
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Bit#(XLEN)) get();
                let r <- axi_rd.response.get();
                return r.data;
            endmethod
        endinterface
    endinterface

endmodule

endpackage