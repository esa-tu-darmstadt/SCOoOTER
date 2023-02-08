package Smiths;

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

(* synthesize *)
module mkSmiths(PredIfc) provisos (
    // TODO: this is ugly
    Add#(0, TExp#(BITS_PHT), entries_t),

    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);

    Vector#(entries_t, Reg#(UInt#(2))) pht <- replicateM(mkReg(0));

    rule show_buffer;
        dbg_print(PRED, $format("-----------------"));
        for(Integer i = 0; i < valueOf(entries_t); i = i+1) begin
            Bit#(BITS_PHT) tag_ext = fromInteger(i);
            dbg_print(PRED, $format(fshow(tag_ext), " ", fshow(pht[i])));
        end
    endrule

    function Bit#(BITS_PHT) pc_to_pht_idx(Bit#(XLEN) pc) = truncate(pc>>2);
    function Bool matches_idx(Bit#(BITS_PHT) test_idx, Maybe#(TrainPrediction) train) = (train matches tagged Valid .tv &&& pc_to_pht_idx(tv.pc) == test_idx ? True : False);

    FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(issuewidth_log_t))) trains <- mkPipelineFIFO();

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

    Vector#(IFUINST, Wire#(Bit#(XLEN))) reqs <- replicateM(mkWire());
    Vector#(IFUINST, Server#(Bit#(XLEN), Prediction)) pred_ifc = ?;
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        pred_ifc[i] = (interface Server;
            interface Put request;
                method Action put(Bit#(XLEN) pc);
                    reqs[i] <= pc;
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

    interface Put train = toPut(trains);

    interface predict_direction = pred_ifc;

endmodule

endpackage