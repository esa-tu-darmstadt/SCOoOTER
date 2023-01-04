package Fetch;

import BlueAXI :: *;
import Types :: *;
import Interfaces :: *;
import GetPut :: *;
import Inst_Types :: *;
import Decode :: *;
import FIFO :: *;
import SpecialFIFOs :: *;
import MIMO :: *;
import Vector :: *;
import Debug::*;

module mkFetch(IFU) provisos(
        Mul#(XLEN, IFUINST, ifuwidth) //the width of the IFU axi must be as large as the size of a word times the issuewidth
);

    //AXI for mem access
    AXI4_Master_Rd#(XLEN, ifuwidth, 0, 0) axi <- mkAXI4_Master_Rd(0, 0, False);

    //pc points to next instruction to load
    //pc is a CREG, port 2 is used for fetching the next instruction
    // port 1 is used to redirect the program counter
    //port 0 is used to advance the PC
    Reg#(Bit#(XLEN)) pc[3] <- mkCReg(3, fromInteger(valueof(RESETVEC)));
    Reg#(Bit#(3)) epoch[2] <- mkCReg(2, 0);
    FIFO#(Bit#(XLEN)) inflight_pcs <- mkPipelineFIFO();
    FIFO#(Bit#(3)) inflight_epoch <- mkPipelineFIFO();
    //holds outbound Instruction and PC
    FIFO#(Vector#(IFUINST, Tuple2#(Bit#(32), Bit#(32)))) fetched_inst <- mkPipelineFIFO();
    FIFO#(MIMO::LUInt#(IFUINST)) fetched_amount <- mkPipelineFIFO();


    //Requests data from memory
    //Explicit condition: Fires if the previous read has been evaluated
    // Due to the PC FIFO
    rule requestRead;
        axi4_read_data(axi, pc[2], 0);
        inflight_pcs.enq(pc[2]);
        inflight_epoch.enq(epoch[1]);
    endrule

    rule dropReadResp (inflight_epoch.first() != epoch[1]);
        let r <- axi.response.get;
        inflight_pcs.deq();
        inflight_epoch.deq();
        dbg_print(Fetch, $format("drop read"));
    endrule

    // Evaluates fetched instructions if there is enough space in the instruction window
    // TODO: make enqueued value dynamic
    rule getReadResp (inflight_epoch.first() == epoch[1]);
        let r <- axi.response.get;
        Bit#(ifuwidth) dat = r.data;
        let acqpc = inflight_pcs.first(); inflight_pcs.deq();
        inflight_epoch.deq();

        Vector#(IFUINST, Tuple2#(Bit#(32), Bit#(32))) instructions = newVector; // temporary inst storage
        
        Bit#(XLEN) startpoint = (acqpc>>2)%fromInteger(valueOf(IFUINST))*32; // pos of first useful instruction

        MIMO::LUInt#(IFUINST) amount = unpack(truncate( fromInteger(valueOf(IFUINST)) - (acqpc>>2)%fromInteger(valueOf(IFUINST)))); // how many inst were usefully extracted // TODO: make type smaller

        // Extract instructions
        // two conditions needed to keep static elaboration working
        for(Integer i = 0; i < valueOf(IFUINST); i=i+1) begin
            if(fromInteger(i) < amount) begin
                Bit#(XLEN) iword = dat[startpoint+fromInteger(i)*32+31 : startpoint+fromInteger(i)*32];
                instructions[i] = tuple2(iword, acqpc + (fromInteger(i)*4));
            end
        end

        // enq gathered instructions
        fetched_inst.enq(instructions);
        fetched_amount.enq(amount);

        // advance program counter
        // TODO: branch predictor
        pc[0] <= acqpc + (pack(extend(amount)) << 2);
    endrule

    interface ifu_axi = axi.fab;
    method Action redirect(Bit#(XLEN) newpc);
        pc[1] <= newpc;
        dbg_print(Fetch, $format("Redirected: ", newpc));
        epoch[0] <= epoch[0]+1;
        fetched_inst.clear();
    endmethod
    method MIMO::LUInt#(IFUINST) count                                  = fetched_amount.first;
    method Action deq();
            fetched_inst.deq();
            fetched_amount.deq();
    endmethod
    method Vector#(IFUINST, Tuple2#(Bit#(32), Bit#(32))) first() = fetched_inst.first;


endmodule

endpackage