package RVController;

import Vector::*;
import ClientServer::*;
import Types::*;
import GetPut::*;
import FIFO::*;
import SpecialFIFOs::*;
import Interfaces::*;

/*

RVController emulates the TaPaSCo-RISC-V interface for result output and job termination.
A value can be returned via the input address and a write to the interupt address terminates simulation.
A print register has also been introduced to allow test programs to print output.

*/

// RVController offset defines
typedef 'h0010 RV_CONTROLLER_RETURN_ADDRESS;
typedef 'h4000 RV_CONTROLLER_INTERRUPT_ADDRESS;
typedef 'h8000 RV_CONTROLLER_PRINT_ADDRESS;


interface RVCIFC;
    // memory bus
    interface MemMappedIFC#(16) memory_bus;
    // signals to testbench
    method Bit#(XLEN) retval;
    method Bool done; 
endinterface

module mkRVController(RVCIFC) provisos (
    Log#(NUM_CPU, cpu_idx_t),
    Add#(1, cpu_idx_t, amo_cpu_idx_t) // memory bus ID to select cpu and AMO/normal access

);

    // register state
    Reg#(Bit#(XLEN)) return_r <- mkRegU();
    Reg#(Bool) done_r <- mkReg(False);

    // storage of memory bus IDs
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_r_fifo <- mkSizedFIFO(4);
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_w_fifo <- mkSizedFIFO(4);
    // store read value for one cycle
    Reg#(Bit#(32)) read_val <- mkRegU();

    // connection to memory bus
    interface MemMappedIFC memory_bus;

        // reading registers
        // RVController does not support reading here since it is only used to communicate results back to the TB
        // hence we return dummy values
        interface Server mem_r;
            interface Put request;
                method Action put(Tuple2#(UInt#(16), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    inflight_ids_r_fifo.enq(tpl_2(req));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get();
                    inflight_ids_r_fifo.deq();
                    return tuple2(0, inflight_ids_r_fifo.first());
                endmethod
            endinterface
        endinterface

        // writing registers
        // we ignore strobes here for the time being
        interface Server mem_w;
            interface Put request;
                method Action put(Tuple4#(UInt#(16), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    case (tpl_1(req))
                        fromInteger(valueOf(RV_CONTROLLER_INTERRUPT_ADDRESS)):
                            begin
                                // update status
                                done_r <= True;
                            end
                        fromInteger(valueOf(RV_CONTROLLER_RETURN_ADDRESS)):
                            begin
                                // store return value
                                return_r <= tpl_2(req);
                            end
                        fromInteger(valueOf(RV_CONTROLLER_PRINT_ADDRESS)):
                            begin
                                $write("%c", tpl_2(req)[7:0]);
                            end
                    endcase
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

    // forward registers to testbench
    method Bit#(XLEN) retval = return_r._read();
    method Bool done = done_r._read(); 

endmodule

endpackage