package Frontend;

import Fetch::*;
import Decode::*;
import Types::*;
import Inst_Types::*;
import Interfaces::*;
import BlueAXI::*;
import GetPut::*;
import Connectable :: *;
import Vector::*;
import GetPutCustom::*;
import BTB::*;
import AlwaysUntaken::*;
import Gshare::*;
import Gskewed::*;
import Smiths::*;

// this package contains the frontend components of the core
// the frontend fetches instructions and provides them to the exec core

interface FrontendIFC;
    interface AXI4_Master_Rd_Fab#(XLEN, TMul#(XLEN, IFUINST), 0, 0) imem_axi;
    method Action redirect(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)) in);
    interface GetSC#(DecodeResponse, UInt#(TLog#(TAdd#(ISSUEWIDTH, 1)))) decoded_inst;
    interface Put#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) train;
endinterface

`ifdef SYNTH_SEPARATE_BLOCKS
    (* synthesize *)
`endif
module mkFrontend(FrontendIFC);

    // units
    let ifu <- mkFetch();
    let decode <- mkDecode();

    // predictors
    let btb <- mkBTB();
    let dir_pred <- case (valueOf(BRANCHPRED))
        0: mkAlwaysUntaken();
        1: mkSmiths();
        2: mkGshare();
        3: mkGskewed();
    endcase;

    // CONNECT UNITS
    
    // pass instructions forward
    mkConnection(ifu.instructions, decode.instructions);

    // connect predictors to IFU
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        mkConnection(ifu.predict_direction[i], dir_pred.predict_direction[i]);
    end
    mkConnection(ifu.predict_target, btb.predict);

    // connect outside training stimuli
    interface Put train;
        method Action put(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1)))) in);
            btb.train.put(in);
            dir_pred.train.put(in);
        endmethod
    endinterface

    // connect mispredict signals
    method Action redirect(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)) in);
        ifu.redirect(in);
    endmethod

    // output from the frontend to the exec core
    interface GetSC decoded_inst = decode.decoded_inst;

    // port to main mem
    interface imem_axi = ifu.imem_axi;
endmodule

endpackage