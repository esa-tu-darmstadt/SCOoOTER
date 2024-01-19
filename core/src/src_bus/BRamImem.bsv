package BRamImem;

import Types::*;
import ClientServer::*;
import BRAM :: *;
import DefaultValue::*;
import FIFO::*;

interface ImemIFC;
    interface Server#(Tuple2#(UInt#(XLEN), Bit#(TLog#(NUM_CPU))), Tuple2#(Bit#(TMul#(XLEN, IFUINST)), Bit#(TLog#(NUM_CPU)))) mem;
endinterface

module mkBramImem#(String contentPreload)(ImemIFC) provisos (
        Mul#(XLEN, IFUINST, ifuwidth),
        // BRAMs are word addressed, thus we calculate the size in words
        Div#(BRAMSIZE, 4, bram_word_num_t),
        Log#(NUM_CPU, cpu_idx_t)
    );
    // create a fitting BRAM
    BRAM_Configure cfg_i = defaultValue;
    cfg_i.allowWriteResponseBypass = True;
    cfg_i.memorySize = valueOf(bram_word_num_t);
    cfg_i.loadFormat = tagged Hex contentPreload;
    cfg_i.latency = 1;
    BRAM1Port#(Bit#(XLEN), Bit#(ifuwidth)) ibram <- mkBRAM1Server(cfg_i);

    FIFO#(Bit#(cpu_idx_t)) inflight_ids_inst <- mkSizedFIFO(4);


    interface Server mem;
        interface Put request;
            method Action put(Tuple2#(UInt#(XLEN), Bit#(TLog#(NUM_CPU))) req);
                ibram.portA.request.put(BRAMRequest{
                    write: False,
                    responseOnWrite: False,
                    address: (pack(tpl_1(req))>>2)/fromInteger(valueOf(IFUINST)),
                    datain: ?
                });
                inflight_ids_inst.enq(tpl_2(req));
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Tuple2#(Bit#(TMul#(XLEN, IFUINST)), Bit#(TLog#(NUM_CPU)))) get();
                let r <- ibram.portA.response.get();
                inflight_ids_inst.deq();
                return tuple2(r, inflight_ids_inst.first());
            endmethod
        endinterface
    endinterface

endmodule

endpackage