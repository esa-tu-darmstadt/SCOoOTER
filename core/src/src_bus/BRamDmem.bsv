package BRamDmem;

import Types::*;
import ClientServer::*;
import BRAM :: *;
import DefaultValue::*;
import FIFO::*;

interface DmemIFC;
    interface Server#(Tuple2#(UInt#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1))), Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) mem_r;
    interface Server#(Tuple4#(UInt#(XLEN), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))), Bit#(TAdd#(TLog#(NUM_CPU), 1))) mem_w;
endinterface


module mkBramDmem#(String contentPreload)(DmemIFC) provisos (
        // BRAMs are word addressed, thus we calculate the size in words
        Div#(BRAMSIZE, 4, bram_word_num_t),
        Log#(NUM_CPU, cpu_idx_t),
        Add#(1, cpu_idx_t, amo_cpu_idx_t),
        Log#(bram_word_num_t, addr_len_t)
    );
    // create a fitting BRAM
    BRAM_Configure cfg_i = defaultValue;
    cfg_i.allowWriteResponseBypass = True;
    cfg_i.memorySize = valueOf(bram_word_num_t);
    cfg_i.loadFormat = tagged Hex contentPreload;
    cfg_i.latency = 1;
    BRAM2PortBE#(UInt#(addr_len_t), Bit#(XLEN), 4) dbram <- mkBRAM2ServerBE(cfg_i);

    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_r_fifo <- mkSizedFIFO(4);
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_w_fifo <- mkSizedFIFO(4);

    interface Server mem_r;
        interface Put request;
            method Action put(Tuple2#(UInt#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                dbram.portA.request.put(BRAMRequestBE{
                    writeen: 0,
                    responseOnWrite: False,
                    address: truncate(((tpl_1(req)-fromInteger(valueOf(BRAMSIZE)))>>2)),
                    datain: ?
                });
                inflight_ids_r_fifo.enq(tpl_2(req));
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get();
                let r <- dbram.portA.response.get();
                inflight_ids_r_fifo.deq();
                return tuple2(r, inflight_ids_r_fifo.first());
            endmethod
        endinterface
    endinterface

    interface Server mem_w;
        interface Put request;
            method Action put(Tuple4#(UInt#(XLEN), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                dbram.portB.request.put(BRAMRequestBE{
                    writeen: tpl_3(req),
                    responseOnWrite: True,
                    address: truncate(((tpl_1(req)-fromInteger(valueOf(BRAMSIZE)))>>2)),
                    datain: tpl_2(req)
                });
                inflight_ids_w_fifo.enq(tpl_4(req));
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) get();
                let r <- dbram.portB.response.get();
                inflight_ids_w_fifo.deq();
                return inflight_ids_w_fifo.first();
            endmethod
        endinterface
    endinterface
endmodule

endpackage