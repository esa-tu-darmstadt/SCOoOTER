package CLINT;

import Vector::*;
import ClientServer::*;
import Types::*;
import GetPut::*;
import FIFO::*;
import SpecialFIFOs::*;
import Interfaces::*;


/*

The CLINT is the RISC-V interrupt component which generates timer interrupts.
CLINT has a timer register and one compare register per HART. Th ose registers are 64 bit wide.

*/


interface CLINTIFC;
    // memory bus
    interface MemMappedIFC#(12) memory_bus;
    // timer interrupt signals to cores
    (* always_ready, always_enabled *)
    method Vector#(NUM_HARTS, Bool) timer_interrupts;
endinterface

module mkCLINT(CLINTIFC) provisos (
    Mul#(NUM_HARTS, 2, num_mtimecmp), // compare register amount (in 32b registers)
    Log#(NUM_CPU, cpu_idx_t),         // id width to track CPUs
    Add#(1, cpu_idx_t, amo_cpu_idx_t) // add a bit to CPU id to encode AMOs or normal request
);

    // register state
    // the memory map first houses the lower bits and afterwards the upper bits!
    // mtime is a single 64b register while mtimecmp is a 64b register per hart
    Vector#(2, Reg#(Bit#(32))) mtime <- replicateM(mkReg(0));
    Vector#(num_mtimecmp, Reg#(Bit#(32))) mtimecmp <- replicateM(mkReg('hffffffff));
    //register map
    let register_map_bus = Vector::append(mtime, mtimecmp);

    // store IDs of memory bus requests
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_r_fifo <- mkSizedFIFO(4);
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_w_fifo <- mkSizedFIFO(4);
    // temporary storage of the read value
    Reg#(Bit#(32)) read_val <- mkRegU();

    // scheduling, preempt increment method if a write is in progreess
    PulseWire write_or_increment <- mkPulseWire();

    // increment mtime
    rule increment if (!write_or_increment);
        // build 64 bit word
        let new_val = {mtime[1], mtime[0]} + 1;
        // cut into 32 bit slices
        mtime[1] <= truncateLSB(new_val);
        mtime[0] <= truncate(new_val);
    endrule

    // connection to memory bus
    interface MemMappedIFC memory_bus;

        // reading registers
        interface Server mem_r;
            interface Put request;
                method Action put(Tuple2#(UInt#(12), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    // store selected register value for returning on next cycle
                    read_val <= register_map_bus[tpl_1(req)>>2];
                    // store request id
                    inflight_ids_r_fifo.enq(tpl_2(req));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get();
                    // dequeue id and provide response
                    inflight_ids_r_fifo.deq();
                    return tuple2(read_val, inflight_ids_r_fifo.first());
                endmethod
            endinterface
        endinterface

        // writing registers
        interface Server mem_w;
            interface Put request;
                method Action put(Tuple4#(UInt#(12), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    // get current and write value as byte vectors to allow for strobe application
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
                    // dequeue id and provide response
                    inflight_ids_w_fifo.deq();
                    return inflight_ids_w_fifo.first();
                endmethod
            endinterface
        endinterface
    endinterface

    // generate interrupt signals
    method Vector#(NUM_HARTS, Bool) timer_interrupts;
        let mtime_64b = {mtime[1], mtime[0]}; // build mtime 64 bit word

        Vector#(NUM_HARTS, Bool) local_int_flags = replicate(False);
        // for every HART, compare compare registers to mtime
        for(Integer i = 0; i < valueOf(NUM_HARTS); i=i+1)
            local_int_flags[i] = (mtime_64b >= {mtimecmp[2*i+1], mtimecmp[2*i]});
        return local_int_flags;
    endmethod

endmodule

endpackage