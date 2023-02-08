package Gshare;

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
import Ehr::*;

(* synthesize *)
module mkGshare(PredIfc) provisos (
    // TODO: this is ugly
    Add#(0, TExp#(BITS_PHT), entries_t),

    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),
    Add#(offset_bhr_t, BITS_BHR, BITS_PHT)
);

    Vector#(entries_t, Reg#(UInt#(2))) pht <- replicateM(mkReg(0));
    Array#(Reg#(Bit#(BITS_BHR))) bhr <- mkCReg(2, 0);

    function Bit#(BITS_PHT) pc_to_pht_idx(Bit#(XLEN) pc, Bit#(BITS_BHR) history) = truncate(pc>>2)^(extend(history)<<valueOf(offset_bhr_t));
    function Bool matches_idx(Bit#(BITS_PHT) test_idx, Maybe#(TrainPrediction) train) = (train matches tagged Valid .tv &&& pc_to_pht_idx(tv.pc, tv.history) == test_idx ? True : False);

    FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(issuewidth_log_t))) trains <- mkPipelineFIFO();

    function Bool check_if_misprediction(Maybe#(TrainPrediction) in) = (isValid(in) && in.Valid.miss);

    rule elapse_train;
        let in = trains.first(); trains.deq();
        for(Integer i = 0; i < valueOf(entries_t); i = i+1) begin
            let found_idx = Vector::findIndex(matches_idx(fromInteger(i)), tpl_1(in));
            if(found_idx matches tagged Valid .idx &&& 
                extend(idx) < tpl_2(in) &&& 
                tpl_1(in)[idx].Valid.branch) begin
                    //$display("train: ", fshow(tpl_1(in)[idx]));
                    if (tpl_1(in)[idx].Valid.taken) begin
                        if (pht[i] != 'b11) pht[i] <= pht[i] + 1;
                    end else begin
                        if (pht[i] != 'b00) pht[i] <= pht[i] - 1;
                    end
            end
        end
    endrule

    Ehr#(TAdd#(1, IFUINST), Bit#(issuewidth_log_t)) predicted_count <- mkEhr(0);
    Ehr#(TAdd#(2, IFUINST), Bit#(BITS_BHR)) predicted_bhrs <- mkEhr(0);
    Ehr#(TAdd#(1, IFUINST), Bool) predicted_results <- mkEhr(False);

    rule canonicalize_bhr;
        if (predicted_count[valueOf(IFUINST)] > 0) begin
            bhr[0] <= truncate({bhr[0] << predicted_count[valueOf(IFUINST)]-1, pack(predicted_results[valueOf(IFUINST)])});
            predicted_results[valueOf(IFUINST)] <= False;
            predicted_count[valueOf(IFUINST)] <= 0;
        end
    endrule

    rule init_bhr_tracking;
        predicted_bhrs[0] <= bhr[0];
    endrule

    Vector#(IFUINST, Wire#(Bool)) outbound_results <- replicateM(mkDWire(False));
    Vector#(IFUINST, Wire#(Bit#(XLEN))) reqs <- replicateM(mkWire());
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        rule generate_prediction;
            Bit#(BITS_BHR) history = bhr[0] << predicted_count[i];
            Bool taken = pht[pc_to_pht_idx(reqs[i], history)] >= 2'b10;
            predicted_bhrs[i+1] <= history;

            if(!predicted_results[i]) begin
                predicted_count[i] <= predicted_count[i] + 1;
                predicted_results[i] <= taken;
                outbound_results[i] <= taken;
            end

            //$display("pred: %x %b ", reqs[i], history, taken); 
        endrule
    end

    Vector#(IFUINST, Wire#(Bit#(BITS_BHR))) outbound_history <- replicateM(mkWire());
    for(Integer i = 0; i < valueOf(IFUINST); i=i+1) begin
        rule progress;
            outbound_history[i] <= predicted_bhrs[i+2];
        endrule
    end


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
                        return Prediction{pred: outbound_results[i], history: outbound_history[i]};
                    endactionvalue
                endmethod
            endinterface
        endinterface);
    end

    interface Put train;
        method Action put(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(issuewidth_log_t)) in);
            let misp_idx = Vector::findIndex(check_if_misprediction, tpl_1(in));
            if(misp_idx matches tagged Valid .v &&& extend(v) < tpl_2(in)) begin
                let misp = tpl_1(in)[v].Valid;
                // update BHR with correct value
                bhr[1] <= misp.branch ? truncate({misp.history, pack(misp.taken)}) : misp.history;
                //$display("redirect BHR: %b", misp.branch ? truncate({misp.history, pack(misp.taken)}) : misp.history);
            end
            trains.enq(in);
        endmethod
    endinterface

    interface predict_direction = pred_ifc;

endmodule

endpackage