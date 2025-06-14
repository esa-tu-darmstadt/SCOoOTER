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
import GetPut::*;
import ClientServer::*;

// this package contains the frontend components of the core
// the frontend fetches instructions and provides them to the exec core

interface FrontendIFC;
    interface Client#(Bit#(XLEN), Bit#(TMul#(XLEN, IFUINST))) read_inst;
    method Action redirect(Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) in);
    interface GetSC#(DecodeResponse, Bit#(ISSUEWIDTH)) decoded_inst;
    interface Put#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) train;
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
    
    // pass instructions from fetch to decode
    mkConnection(ifu.instructions, decode.instructions);

    // connect predictors to IFU
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        mkConnection(ifu.predict_direction[i], dir_pred.predict_direction[i]);
    end
    mkConnection(ifu.predict_target, btb.predict);

    // notify predictors of currently-predicted thread
    // each thread has its own BHR
    rule propagate_thread_id;
        dir_pred.current_thread(ifu.current_thread());
    endrule

    // connect training stimuli from commit to the predictors
    interface Put train;
        method Action put(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)) in);
            btb.train.put(in);
            dir_pred.train.put(in);
        endmethod
    endinterface

    // connect mispredict signals
    method Action redirect(Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) in);
        ifu.redirect(in);
    endmethod

    // output from the frontend to the exec core
    interface GetSC decoded_inst = decode.decoded_inst;

    // port to instruction memory
    interface read_inst = ifu.read;
endmodule

endpackage