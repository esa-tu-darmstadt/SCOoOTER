package Smiths;

/*
  This is the simplest branch direction predictor.
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
    // For some reason, the compiler does not like this with a proviso
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
    function Bit#(BITS_PHT) pc_to_pht_idx(Bit#(XLEN) pc) = truncate(pc>>2);
    // check if a train entry matches an index
    function Bool matches_idx(Bit#(BITS_PHT) test_idx, Maybe#(TrainPrediction) train) = (train matches tagged Valid .tv &&& pc_to_pht_idx(tv.pc) == test_idx ? True : False);
    // incoming training signals
    FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(issuewidth_log_t))) trains <- mkPipelineFIFO();

    // train the predictor
    rule elapse_train;
        let in = trains.first(); trains.deq();
        for(Integer i = 0; i < valueOf(entries_t); i = i+1) begin
                let found_idx = Vector::findIndex(matches_idx(fromInteger(i)), tpl_1(in));
                if(found_idx matches tagged Valid .idx &&& extend(idx) < tpl_2(in)) begin
                    if (tpl_1(in)[idx].Valid.taken) begin
                        if (pht[i] != 'b11) pht[i] <= pht[i] + 1;
                    end else begin
                        if (pht[i] != 'b00) pht[i] <= pht[i] - 1;
                    end
                end
            end
    endrule

    // build the prediction interface
    Vector#(IFUINST, Wire#(Bit#(XLEN))) reqs <- replicateM(mkWire());
    Vector#(IFUINST, Server#(Tuple2#(Bit#(XLEN),Bool), Prediction)) pred_ifc = ?;
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        pred_ifc[i] = (interface Server;
            interface Put request;
                method Action put(Tuple2#(Bit#(XLEN),Bool) in);
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