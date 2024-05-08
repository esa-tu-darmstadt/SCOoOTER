package BRamImem;

import Types::*;
import ClientServer::*;
import BRAM :: *;
import DefaultValue::*;
import FIFO::*;

/*

IMEM wrapper for testbench - uses BRAMs which may be preloaded

*/


interface ImemIFC;
    interface Server#(Tuple2#(UInt#(XLEN), Bit#(TLog#(NUM_CPU))), Tuple2#(Bit#(TMul#(XLEN, IFUINST)), Bit#(TLog#(NUM_CPU)))) mem;
endinterface

module mkBramImem#(String contentPreload)(ImemIFC) provisos (
        Mul#(XLEN, IFUINST, ifuwidth),
        // BRAMs are word addressed, thus we calculate the size in words
        Div#(SIZE_IMEM, 4, bram_logical_word_num_t), // words as seen by CPU
        Div#(bram_logical_word_num_t, IFUINST, bram_physical_word_num_t), // since we may read multiple instructions per cycle, we must widen the bus
        Log#(bram_physical_word_num_t, bram_addrwidth_t), // calculate address width based on word amount
        Log#(NUM_CPU, cpu_idx_t) // calculate CPU id width
    );
    // create a fitting BRAM
    BRAM_Configure cfg_i = defaultValue;
    cfg_i.memorySize = valueOf(bram_physical_word_num_t); // set size
    cfg_i.loadFormat = tagged Hex contentPreload; // load program
    cfg_i.latency = 1; // latency = 1 - response on next cycle
    BRAM1Port#(UInt#(bram_addrwidth_t), Bit#(ifuwidth)) ibram <- mkBRAM1Server(cfg_i);

    // store memory bus ID - only read, write unsupported on IMEM
    FIFO#(Bit#(cpu_idx_t)) inflight_ids_inst <- mkSizedFIFO(4);


    interface Server mem;
        interface Put request;
            method Action put(Tuple2#(UInt#(XLEN), Bit#(TLog#(NUM_CPU))) req);
                // adapt request to BRAM request
                ibram.portA.request.put(BRAMRequest{
                    write: False, // only reading, no write
                    responseOnWrite: False, // we don't write anyways
                    address: truncate((tpl_1(req)>>2)/fromInteger(valueOf(IFUINST))), // turn byte address into word address
                    datain: 0
                });
                // store request ID
                inflight_ids_inst.enq(tpl_2(req));
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Tuple2#(Bit#(TMul#(XLEN, IFUINST)), Bit#(TLog#(NUM_CPU)))) get();
                // return BRAM response to memory bus
                let r <- ibram.portA.response.get();
                inflight_ids_inst.deq();
                return tuple2(r, inflight_ids_inst.first());
            endmethod
        endinterface
    endinterface

endmodule

endpackage