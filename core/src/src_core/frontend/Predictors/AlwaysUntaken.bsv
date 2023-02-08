package AlwaysUntaken;

import Interfaces::*;
import Vector::*;
import Inst_Types::*;
import GetPut::*;
import Types::*;
import ClientServer::*;

(* synthesize *)
module mkAlwaysUntaken(PredIfc) provisos (
    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);

    Vector#(IFUINST, Server#(Bit#(XLEN), Prediction)) pred_ifc = ?;
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        pred_ifc[i] = (interface Server;
            interface Put request;
                method Action put(Bit#(XLEN) x1);
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
        method Action put(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(issuewidth_log_t)) in);
        endmethod
    endinterface

endmodule

endpackage