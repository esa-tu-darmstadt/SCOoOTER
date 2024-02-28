package CLINT;

import Vector::*;
import ClientServer::*;
import Types::*;
import GetPut::*;
import FIFO::*;
import SpecialFIFOs::*;
import Interfaces::*;

interface CLINTIFC;
    interface MemMappedIFC#(12) memory_bus;
    (* always_ready, always_enabled *)
    method Vector#(NUM_HARTS, Bool) timer_interrupts;
endinterface

module mkCLINT(CLINTIFC) provisos (
    Mul#(NUM_HARTS, 2, num_mtimecmp),
    Log#(NUM_CPU, cpu_idx_t),
    Add#(1, cpu_idx_t, amo_cpu_idx_t)

);

    // register state
    // the memory map first houses the lower bits and afterwards the upper bits!
    // mtime is a single 64b register while mtimecmp is a 64b register per hart
    Vector#(2, Reg#(Bit#(32))) mtime <- replicateM(mkReg(0));
    Vector#(num_mtimecmp, Reg#(Bit#(32))) mtimecmp <- replicateM(mkReg('hffffffff));
    //register map
    let register_map_bus = Vector::append(mtime, mtimecmp);

    // forwarding of data
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_r_fifo <- mkSizedFIFO(4);
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_w_fifo <- mkSizedFIFO(4);
    Reg#(Bit#(32)) read_val <- mkRegU();

    // scheduling
    PulseWire write_or_increment <- mkPulseWire();

    rule increment if (!write_or_increment);
        let new_val = {mtime[1], mtime[0]} + 1;
        mtime[1] <= truncateLSB(new_val);
        mtime[0] <= truncate(new_val);
    endrule

    // connection to memory bus
    interface MemMappedIFC memory_bus;

        // reading registers
        interface Server mem_r;
            interface Put request;
                method Action put(Tuple2#(UInt#(12), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    read_val <= register_map_bus[tpl_1(req)>>2];
                    inflight_ids_r_fifo.enq(tpl_2(req));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get();
                    inflight_ids_r_fifo.deq();
                    return tuple2(read_val, inflight_ids_r_fifo.first());
                endmethod
            endinterface
        endinterface

        // writing registers
        interface Server mem_w;
            interface Put request;
                method Action put(Tuple4#(UInt#(12), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    Vector#(4, Bit#(8)) current_value = unpack(register_map_bus[tpl_1(req)>>2]);
                    Vector#(4, Bit#(8)) write_value = unpack(tpl_2(req));
                    // apply strobe signals
                    for(Integer i = 0; i < 4; i=i+1)
                        if(tpl_3(req)[i] == 1) current_value[i] = write_value[i];
                    // write result
                    register_map_bus[tpl_1(req)>>2] <= pack(current_value);
                    // fix scheduling by preempting increment when writing mtime
                    if ((tpl_1(req)>>2) < 2) write_or_increment.send();
                    // save id
                    inflight_ids_w_fifo.enq(tpl_4(req));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) get();
                    inflight_ids_w_fifo.deq();
                    return inflight_ids_w_fifo.first();
                endmethod
            endinterface
        endinterface
    endinterface

    // generate interrupt signals
    method Vector#(NUM_HARTS, Bool) timer_interrupts;
        let mtime_64b = {mtime[1], mtime[0]};

        Vector#(NUM_HARTS, Bool) local_int_flags = ?;
        for(Integer i = 0; i < valueOf(NUM_HARTS); i=i+1)
            local_int_flags[i] = (mtime_64b >= {mtimecmp[2*i+1], mtimecmp[2*i]});
        return local_int_flags;
    endmethod

endmodule

endpackage