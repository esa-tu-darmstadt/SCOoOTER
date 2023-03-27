package Gskewed;

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
import BuildVector::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkGskewed(PredIfc) provisos (
    // TODO: this is ugly
    Add#(0, TExp#(BITS_PHT), entries_t),

    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),
    Add#(offset_bhr_t, BITS_BHR, BITS_PHT)
);
    // hashing function for GSKEWED combination functions
    function Bit#(BITS_PHT) hash_fwd(Bit#(BITS_PHT) val) = {val[0]^val[valueOf(BITS_PHT)-1], truncate(val >> 1)};
    function Bit#(BITS_PHT) hash_bwd(Bit#(BITS_PHT) val) = {truncate(val), val[0]^val[valueOf(BITS_PHT)-1]};

    // three different PC and BHR combinatory functions
    function Bit#(BITS_PHT) hash1(Bit#(BITS_PHT) addr, Bit#(BITS_PHT) hist) = hash_bwd(addr)^hash_fwd(hist)^hist;
    function Bit#(BITS_PHT) hash2(Bit#(BITS_PHT) addr, Bit#(BITS_PHT) hist) = hash_bwd(addr)^hash_fwd(hist)^addr;
    function Bit#(BITS_PHT) hash3(Bit#(BITS_PHT) addr, Bit#(BITS_PHT) hist) = hash_fwd(addr)^hash_bwd(hist)^hist;

    // our three PHTs
    Vector#(entries_t, Reg#(UInt#(2))) pht1 <- replicateM(mkReg(0));
    Vector#(entries_t, Reg#(UInt#(2))) pht2 <- replicateM(mkReg(0));
    Vector#(entries_t, Reg#(UInt#(2))) pht3 <- replicateM(mkReg(0));

    // function to align BHR with PC if BHR is shorter
    function Bit#(BITS_PHT) extend_bhr(Bit#(BITS_BHR) b) = extend(b)<<valueOf(offset_bhr_t);

    // function to check if a PHT value refers to taken or untaken
    function Bool check_pht(Vector#(entries_t, Reg#(UInt#(2))) pht, Bit#(BITS_PHT) idx) = pht[idx] >= 2'b10;

    // branch history register
    Array#(Reg#(Bit#(BITS_BHR))) bhr <- mkCReg(2, 0);

    // test whether a idx matches a training input
    function Bool matches_idx1(Bit#(BITS_PHT) test_idx, Maybe#(TrainPrediction) train) = (train matches tagged Valid .tv &&& hash1(truncate(tv.pc>>2), extend_bhr(tv.history)) == test_idx ? True : False);
    function Bool matches_idx2(Bit#(BITS_PHT) test_idx, Maybe#(TrainPrediction) train) = (train matches tagged Valid .tv &&& hash2(truncate(tv.pc>>2), extend_bhr(tv.history)) == test_idx ? True : False);
    function Bool matches_idx3(Bit#(BITS_PHT) test_idx, Maybe#(TrainPrediction) train) = (train matches tagged Valid .tv &&& hash3(truncate(tv.pc>>2), extend_bhr(tv.history)) == test_idx ? True : False);

    // FIFO for incoming training requests
    FIFO#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(issuewidth_log_t))) trains <- mkPipelineFIFO();

    // function to check if a train struct was caused by misprediction
    function Bool check_if_misprediction(Maybe#(TrainPrediction) in) = (isValid(in) && in.Valid.miss);

    // train the three predictors
    rule elapse_train1;
        let in = trains.first();
        for(Integer i = 0; i < valueOf(entries_t); i = i+1) begin
            let found_idx = Vector::findIndex(matches_idx1(fromInteger(i)), tpl_1(in));
            if(found_idx matches tagged Valid .idx &&& extend(idx) < tpl_2(in) &&& tpl_1(in)[idx].Valid.branch) begin
                if (tpl_1(in)[idx].Valid.taken) begin
                    if (pht1[i] != 'b11) pht1[i] <= pht1[i] + 1;
                end else begin
                    if (pht1[i] != 'b00) pht1[i] <= pht1[i] - 1;
                end
            end
        end
    endrule
    rule elapse_train2;
        let in = trains.first();
        for(Integer i = 0; i < valueOf(entries_t); i = i+1) begin
            let found_idx = Vector::findIndex(matches_idx2(fromInteger(i)), tpl_1(in));
            if(found_idx matches tagged Valid .idx &&& extend(idx) < tpl_2(in) &&& tpl_1(in)[idx].Valid.branch) begin
                if (tpl_1(in)[idx].Valid.taken) begin
                    if (pht2[i] != 'b11) pht2[i] <= pht2[i] + 1;
                end else begin
                    if (pht2[i] != 'b00) pht2[i] <= pht2[i] - 1;
                end
            end
        end
    endrule
    rule elapse_train3;
        let in = trains.first();
        for(Integer i = 0; i < valueOf(entries_t); i = i+1) begin
            let found_idx = Vector::findIndex(matches_idx3(fromInteger(i)), tpl_1(in));
            if(found_idx matches tagged Valid .idx &&& extend(idx) < tpl_2(in) &&& tpl_1(in)[idx].Valid.branch) begin
                if (tpl_1(in)[idx].Valid.taken) begin
                    if (pht3[i] != 'b11) pht3[i] <= pht3[i] + 1;
                end else begin
                    if (pht3[i] != 'b00) pht3[i] <= pht3[i] - 1;
                end
            end
        end
    endrule
    rule deq_train;
        trains.deq();
    endrule

    // EHRs to hold values between consecutive predictions in a single cycle
    Ehr#(TAdd#(1, IFUINST), Bit#(issuewidth_log_t)) predicted_count <- mkEhr(0);
    Ehr#(TAdd#(2, IFUINST), Bit#(BITS_BHR)) predicted_bhrs <- mkEhr(0);
    Ehr#(TAdd#(1, IFUINST), Bool) predicted_results <- mkEhr(False);

    // after one round of prediction, upate the BHR
    rule canonicalize_bhr;
        if (predicted_count[valueOf(IFUINST)] > 0) begin
            bhr[0] <= truncate({bhr[0] << predicted_count[valueOf(IFUINST)]-1, pack(predicted_results[valueOf(IFUINST)])});
            predicted_results[valueOf(IFUINST)] <= False;
            predicted_count[valueOf(IFUINST)] <= 0;
        end
    endrule
    // before predictiong, set the current BHR as base
    rule init_bhr_tracking;
        predicted_bhrs[0] <= bhr[0];
    endrule

    // real prediction
    Vector#(IFUINST, Wire#(Bool)) outbound_results <- replicateM(mkDWire(False));
    Vector#(IFUINST, Wire#(Tuple2#(Bit#(XLEN),Bool))) reqs <- replicateM(mkWire());
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        rule generate_prediction;
            // for this prediction to matter, all previous ones must be untaken
            Bit#(BITS_BHR) history = bhr[0] << predicted_count[i];
            
            // prediction
            let bhr_ext = extend_bhr(history);
            let idx1 = hash1(truncate(tpl_1(reqs[i])>>2), bhr_ext);
            let idx2 = hash2(truncate(tpl_1(reqs[i])>>2), bhr_ext);
            let idx3 = hash3(truncate(tpl_1(reqs[i])>>2), bhr_ext);

            let results = vec(
                check_pht(pht1, idx1),
                check_pht(pht2, idx2),
                check_pht(pht3, idx3)
            );

            // majority vote
            let count = Vector::countElem(True, results);
            Bool taken = count >= 2 && tpl_2(reqs[i]);

            predicted_bhrs[i+1] <= history;

            // update values for BHR canonicalization
            if(!predicted_results[i]) begin
                predicted_count[i] <= predicted_count[i] + 1;
                predicted_results[i] <= taken;
                outbound_results[i] <= taken;
            end    
        endrule
    end

    // output BHR state such that it can be tracked and restored on misprediction
    Vector#(IFUINST, Wire#(Bit#(BITS_BHR))) outbound_history <- replicateM(mkWire());
    for(Integer i = 0; i < valueOf(IFUINST); i=i+1) begin
        rule progress;
            outbound_history[i] <= predicted_bhrs[i+2];
        endrule
    end

    // generate prediction interfaces
    Vector#(IFUINST, Server#(Tuple2#(Bit#(XLEN),Bool), Prediction)) pred_ifc = ?;
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        pred_ifc[i] = (interface Server;
            interface Put request;
                method Action put(Tuple2#(Bit#(XLEN),Bool) in);
                    reqs[i] <= in;
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
    interface predict_direction = pred_ifc;

    // input for training structures
    interface Put train;
        method Action put(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(issuewidth_log_t)) in);
            let misp_idx = Vector::findIndex(check_if_misprediction, tpl_1(in));
            if(misp_idx matches tagged Valid .v &&& extend(v) < tpl_2(in)) begin
                let misp = tpl_1(in)[v].Valid;
                // update BHR with correct value
                bhr[1] <= misp.branch ? truncate({misp.history, pack(misp.taken)}) : misp.history;
            end
            trains.enq(in);
        endmethod
    endinterface


endmodule

endpackage