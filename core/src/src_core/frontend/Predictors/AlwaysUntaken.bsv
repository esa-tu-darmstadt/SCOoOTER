package AlwaysUntaken;

/*
  This predictor just statically predicts everything as untaken
*/

import Interfaces::*;
import Vector::*;
import Inst_Types::*;
import GetPut::*;
import Types::*;
import ClientServer::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkAlwaysUntaken(PredIfc) provisos (
    // create types to track instruction amount
    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);

    Vector#(IFUINST, Server#(Tuple2#(Bit#(XLEN),Bool), Prediction)) pred_ifc = ?;
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        pred_ifc[i] = (interface Server;
            interface Put request;
                method Action put(Tuple2#(Bit#(XLEN),Bool) x1);
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Prediction) get();
                    actionvalue
                        return Prediction{pred: False, history: ?};
                    endactionvalue
                endmethod
            endinterface
        endinterface);
    end

    interface predict_direction = pred_ifc;

    interface Put train;
        method Action put(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)) in);
        endmethod
    endinterface

endmodule

endpackage