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

module mkFetch(IFU#(ifuwidth, mimodepth)) provisos(
        Mul#(XLEN, IFUINST, ifuwidth), //the width of the IFU axi must be as large as the size of a word times the issuewidth
        Bits#(InstructionPredecode, predecodewidth), //a predecoded instruction is predecodewidth bits wide
        Add#(ISSUEWIDTH, __a, mimodepth), //the depth of the output MIMO should be larger than instructions issued in one cycle
        Add#(IFUINST, __b, mimodepth), //the depth of the output MIMO should be at least as wide as the IFU fetch width
        Mul#(mimodepth, predecodewidth, mimosize), //the output MIMO holds the amount of bits equal to the bit width of a predecoded inst and the mimo depth
        Add#(__c, predecodewidth, mimosize), // the MIMO should hold at least one predecoded instruction
        Add#(__d, 2, mimodepth) // a MIMO must hold at least two elements otherwise it is a FIFO
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
    MIMO#(IFUINST, ISSUEWIDTH, mimodepth, InstructionPredecode) fetched_inst <- mkMIMO(defaultValue); //TODO: buffer size configurable

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
        dbg_print(Fetch, $format("Redirected: ", newpc));
        epoch[0] <= epoch[0]+1;
        fetched_inst.clear();
    endmethod
    method MIMO::LUInt#(mimodepth) count                   = fetched_inst.count;
    method Action deq(MIMO::LUInt#(ISSUEWIDTH) amount)     = fetched_inst.deq(amount);
    method Vector#(ISSUEWIDTH, InstructionPredecode) first = fetched_inst.first;


endmodule

endpackage