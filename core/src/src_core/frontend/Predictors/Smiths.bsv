package Smiths;

/*
  This is the smith branch direction predictor.
*/

import Interfaces::*;
import Vector::*;
import Config::*;
import Inst_Types::*;
import GetPut::*;
import Debug::*;
import FIFO::*;
import SpecialFIFOs::*;
import Types::*;
import ClientServer::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkSmiths(PredIfc) provisos (
    Add#(0, TExp#(BITS_PHT), entries_t),
    // create instruction count tracking types
    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);
    // internal storage
    Vector#(entries_t, Reg#(UInt#(2))) pht <- replicateM(mkReg(0));

    // debug printing
    rule show_buffer;
        dbg_print(PRED, $format("-----------------"));
        for(Integer i = 0; i < valueOf(entries_t); i = i+1) begin
            Bit#(BITS_PHT) tag_ext = fromInteger(i);
            dbg_print(PRED, $format(fshow(tag_ext), " ", fshow(pht[i])));
        end
    endrule

    // function to truncate PC
    function Bit#(BITS_PHT) pc_to_pht_idx(Bit#(PCLEN) pc) = truncate(pc);
    // check if a train entry matches an index
    function Bool matches_idx(Bit#(BITS_PHT) test_idx, Maybe#(TrainPrediction) train) = (train matches tagged Valid .tv &&& pc_to_pht_idx(tv.pc) == test_idx ? True : False);
    // incoming training signals
    FIFO#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) trains <- mkPipelineFIFO();

    // train the predictor
    for(Integer i = 0; i < valueOf(entries_t); i = i+1) begin
    rule elapse_train;
        let in = trains.first();
        let found_idx = Vector::findIndex(matches_idx(fromInteger(i)), in);
        if(found_idx matches tagged Valid .idx) begin
            if (in[idx].Valid.taken) begin
                if (pht[i] != 'b11) pht[i] <= pht[i] + 1;
            end else begin
                if (pht[i] != 'b00) pht[i] <= pht[i] - 1;
            end
        end
    endrule
    end
    rule predictor_deq;
        trains.deq();
    endrule

    // build the prediction interface
    Vector#(IFUINST, Wire#(Bit#(PCLEN))) reqs <- replicateM(mkWire());
    Vector#(IFUINST, Server#(Tuple2#(Bit#(PCLEN),Bool), Prediction)) pred_ifc = ?;
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        pred_ifc[i] = (interface Server;
            interface Put request;
                method Action put(Tuple2#(Bit#(PCLEN),Bool) in);
                    reqs[i] <= tpl_1(in);
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Prediction) get();
                    actionvalue
                        return Prediction{pred: pht[pc_to_pht_idx(reqs[i])] >= 2'b10, history: ?};
                    endactionvalue
                endmethod
            endinterface
        endinterface);
    end

    interface predict_direction = pred_ifc;
    interface Put train = toPut(trains);
endmodule

endpackage