package Fetch;

import BlueAXI :: *;
import Types :: *;
import Interfaces :: *;
import GetPut :: *;
import Inst_Types :: *;
import Decode :: *;
import FIFO :: *;

module mkFetch(IFU);

    AXI4_Master_Rd#(XLEN, IFUWIDTH, 0, 0) axi <- mkAXI4_Master_Rd(1, 1, False);
    Reg#(WORD) pc[3] <- mkCReg(3, fromInteger(valueof(RESETVEC)));
    //Reg#(Bit#(3)) epoch <- mkReg(0);
    FIFO#(WORD) inflight_pcs <- mkSizedFIFO(8);

    rule requestRead;
        axi4_read_data(axi, extend(pc[1]>>4), 0);
        inflight_pcs.enq(pc[1]);
    endrule

    rule advancePC;
        pc[1] <= pc[1]+4*4;
    endrule

    rule getReadResp;
        let r <- axi.response.get;
        Bit#(IFUWIDTH) dat = r.data;
        let acqpc = inflight_pcs.first(); inflight_pcs.deq();
        
        for(Integer i = 0; i < valueOf(IFUWIDTH); i = i + 32) begin
            WORD by = dat[i+31:i];
            print_inst(decode(predecode(by, acqpc + fromInteger(i/8))));
        end
    endrule

    interface ifu_axi = axi.fab;
    method Action redirect(WORD newpc);
        pc[0] <= newpc;
    endmethod

endmodule

endpackage