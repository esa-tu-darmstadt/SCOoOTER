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

module mkFetch(IFU#(ifuwidth, 12)) provisos(
        Mul#(XLEN, IFUINST, ifuwidth),
        Bits#(InstructionPredecode, predecodewidth)
    );

    AXI4_Master_Rd#(XLEN, ifuwidth, 0, 0) axi <- mkAXI4_Master_Rd(1, 1, False);
    Reg#(Bit#(XLEN)) pc[3] <- mkCReg(3, fromInteger(valueof(RESETVEC)));
    Reg#(Bit#(3)) epoch[2] <- mkCReg(2, 0);
    FIFO#(Bit#(XLEN)) inflight_pcs <- mkPipelineFIFO();
    FIFO#(Bit#(3)) inflight_epoch <- mkPipelineFIFO();
    MIMO#(IFUINST, ISSUEWIDTH, 12, InstructionPredecode) fetched_inst <- mkMIMO(defaultValue); //TODO: buffer size configurable

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
        $display("drop read");
    endrule

    // Evaluates fetched instructions if there is enough space in the instruction window
    // TODO: make enqueued value dynamic
    rule getReadResp (fetched_inst.enqReadyN(fromInteger(valueOf(IFUINST))) && inflight_epoch.first() == epoch[1]);
        let r <- axi.response.get;
        Bit#(ifuwidth) dat = r.data;
        let acqpc = inflight_pcs.first(); inflight_pcs.deq();
        inflight_epoch.deq();

        Vector#(IFUINST, InstructionPredecode) instructions = newVector; // temporary inst storage
        
        Bit#(XLEN) startpoint = (acqpc>>2)%fromInteger(valueOf(IFUINST))*32; // pos of first useful instruction

        Bit#(XLEN) amount = 0; // how many inst were usefully extracted // TODO: make type smaller

        // Extract instructions
        // two conditions needed to keep static elaboration working
        for(Bit#(XLEN) i = 0; i < fromInteger(valueOf(ifuwidth)) && startpoint+i < fromInteger(valueOf(ifuwidth)); i = i + fromInteger(valueOf(ILEN))) begin
            Bit#(XLEN) by = dat[startpoint+i+31 : startpoint+i];
            instructions[i/32] = predecode(by, acqpc + (i/8));
            amount = amount + 1;
        end

        // enq gathered instructions
        fetched_inst.enq(unpack(truncate(amount)), instructions);

        // advance program counter
        // TODO: branch predictor
        pc[0] <= acqpc + (amount << 2);
    endrule

    interface ifu_axi = axi.fab;
    method Action redirect(Bit#(XLEN) newpc);
        pc[1] <= newpc;
        $display("redir: ", newpc);
        epoch[0] <= epoch[0]+1;
        fetched_inst.clear();
    endmethod
    interface count = fetched_inst.count;
    interface deq = fetched_inst.deq;
    interface first = fetched_inst.first;


endmodule

endpackage