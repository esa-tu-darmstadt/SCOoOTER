package BRamDmem;

import Types::*;
import ClientServer::*;
import BRAM :: *;
import DefaultValue::*;
import FIFO::*;
import Interfaces::*;

/*

DMEM wrapper for testbench - uses BRAMs which may be preloaded

*/

interface DmemIFC;
    interface MemMappedIFC#(TLog#(SIZE_DMEM)) memory_bus;
endinterface


module mkBramDmem#(String contentPreload)(DmemIFC) provisos (
        // BRAMs are word addressed, thus we calculate the size in words
        Div#(SIZE_DMEM, 4, bram_word_num_t),
        Log#(NUM_CPU, cpu_idx_t), // calculate CPU id width...
        Add#(1, cpu_idx_t, amo_cpu_idx_t), // ... and add one to signify AMO
        Log#(bram_word_num_t, addr_len_t), // calculate address width based on word amount
        Add#(addr_len_t, 2, external_addr_len_t) // add two bits to address for byte-addressing
    );

    // create a fitting BRAM
    BRAM_Configure cfg_i = defaultValue;
    cfg_i.memorySize = valueOf(bram_word_num_t); // set size
    cfg_i.loadFormat = tagged Hex contentPreload; // load program
    cfg_i.latency = 1; // latency = 1 - response on next cycle
    BRAM2PortBE#(UInt#(addr_len_t), Bit#(XLEN), 4) dbram <- mkBRAM2ServerBE(cfg_i);

    // store memory bus IDs
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_r_fifo <- mkSizedFIFO(4);
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_w_fifo <- mkSizedFIFO(4);

    interface MemMappedIFC memory_bus;
        interface Server mem_r;
            interface Put request;
                method Action put(Tuple2#(UInt#(external_addr_len_t), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    // adapt request to BRAM request
                    dbram.portA.request.put(BRAMRequestBE{
                        writeen: 0, // only reading, no write
                        responseOnWrite: False,
                        address: truncate(((tpl_1(req))>>2)), // remove byte-address bits
                        datain: 0 // don't care, write is disabled
                    });
                    // store request ID
                    inflight_ids_r_fifo.enq(tpl_2(req));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get();
                    // return BRAM response to memory bus
                    let r <- dbram.portA.response.get();
                    inflight_ids_r_fifo.deq();
                    return tuple2(r, inflight_ids_r_fifo.first());
                endmethod
            endinterface
        endinterface

        interface Server mem_w;
            interface Put request;
                method Action put(Tuple4#(UInt#(external_addr_len_t), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    // adapt request to BRAM request
                    dbram.portB.request.put(BRAMRequestBE{
                        writeen: tpl_3(req), // strobes enable writing
                        responseOnWrite: True,
                        address: truncate(((tpl_1(req))>>2)), // remove byte-address bits
                        datain: tpl_2(req) // write data
                    });
                    // save id
                    inflight_ids_w_fifo.enq(tpl_4(req));

                    // for CORE-V-Verif, end test if write to magic address
                    `ifdef RVFI
                        UInt#(32) host_addr = `TOHOST;
                        if (tpl_1(req) == truncate(host_addr))
                            $finish();
                        `endif
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) get();
                    // respond with successful write
                    let r <- dbram.portB.response.get();
                    inflight_ids_w_fifo.deq();
                    return inflight_ids_w_fifo.first();
                endmethod
            endinterface
        endinterface
    endinterface
endmodule

endpackage