package Gshare;

/*
  This is the GShare direction predictor
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
import Ehr::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkGshare(PredIfc) provisos (
    Add#(0, TExp#(BITS_PHT), entries_t),
    // create types for instruction amount tracking
    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),
    // we want to XOR the history with the upper part of the PC
    // as the lower PC bits offer more entropy
    Log#(NUM_THREADS, thread_id_t)
);
    // internal storage
    Vector#(entries_t, Ehr#(ISSUEWIDTH, UInt#(2))) pht <- replicateM(mkEhr(0));
    // branch history register
    Vector#(NUM_THREADS, Array#(Reg#(Bit#(BITS_BHR)))) bhr <- replicateM(mkCReg(2, 0));

    Wire#(UInt#(thread_id_t)) thread_id_w <- mkBypassWire();

    // function to combine PC and history into the PHT index
    function Bit#(BITS_PHT) pc_to_pht_idx(Bit#(PCLEN) pc, Bit#(BITS_BHR) history) = truncate(pc^{history, 0});
    // test wether a prediction matches a certain index
    function Bool matches_idx(Bit#(BITS_PHT) test_idx, Maybe#(TrainPrediction) train) = (train matches tagged Valid .tv &&& pc_to_pht_idx(tv.pc, tv.history) == test_idx ? True : False);
    // train signal inputs
    FIFO#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) trains <- mkPipelineFIFO();
    // check if a train signal occurred due to misprediction
    function Bool check_if_misprediction(UInt#(thread_id_t) tid, Maybe#(TrainPrediction) in) = (isValid(in) && in.Valid.miss && in.Valid.thread_id == tid);

    // use training inputs to adjust the counter table
    rule restore_bhr;
        let in = trains.first();

        for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) begin
            // restore BHR in case of misprediction
            let misp = Vector::find(check_if_misprediction(fromInteger(i)), in);
            if(misp matches tagged Valid .v) begin
                // update BHR with correct value
                bhr[i][0] <= v.Valid.branch ? truncate({v.Valid.history, pack(v.Valid.taken)}) : v.Valid.history;
            end
        end
    endrule

    // use training data to update predictor storage
    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
    rule train_predictors;
        let in = trains.first();
            if(in[i] matches tagged Valid .train &&& train.branch) begin
                let idx = pc_to_pht_idx(train.pc, train.history);
                if (train.taken) begin
                    if (pht[idx][i] != 'b11) pht[idx][i] <= pht[idx][i] + 1;
                    dbg_print(PRED, $format("Training+: %h %b", i, pht[idx][i], fshow(in[i])));
                end else begin
                    if (pht[idx][i] != 'b00) pht[idx][i] <= pht[idx][i] - 1;
                    dbg_print(PRED, $format("Training-: %h %b", i, pht[idx][i], fshow(in[i])));
                end
            end
    endrule
    end
    rule deq_train;
        trains.deq();
    endrule

    // EHRs to pass information between the successively predicted instructions
    Ehr#(TAdd#(1, IFUINST), Bit#(issuewidth_log_t)) predicted_count <- mkEhr(0);
    Ehr#(TAdd#(2, IFUINST), Bit#(BITS_BHR)) predicted_bhrs <- mkEhr(0);
    Ehr#(TAdd#(1, IFUINST), Bool) predicted_results <- mkEhr(False);

    // update the global BHR with the post-prediction state
    rule canonicalize_bhr;
        if (predicted_count[valueOf(IFUINST)] > 0) begin
            bhr[thread_id_w][1] <= truncate({bhr[thread_id_w][1] << predicted_count[valueOf(IFUINST)]-1, pack(predicted_results[valueOf(IFUINST)])});
        end
        predicted_results[valueOf(IFUINST)] <= False;
        predicted_count[valueOf(IFUINST)] <= 0;
    endrule

    // write the current BHR to the predictively evolving BHR
    rule init_bhr_tracking;
        predicted_bhrs[0] <= bhr[thread_id_w][1];
    endrule

    // prediction happens here
    // we use EHRs to pass info betwen consecutive predictions in a single cycle
    Vector#(IFUINST, Wire#(Bool)) outbound_results <- replicateM(mkDWire(False));
    Vector#(IFUINST, Wire#(Tuple2#(Bit#(PCLEN), Bool))) reqs <- replicateM(mkWire());
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        rule generate_prediction;
            // all previous predictions must be untaken for this one to matter
            Bit#(BITS_BHR) history = bhr[thread_id_w][1] << predicted_count[i];
            // check PHT for prediction
            Bool taken = (pht[pc_to_pht_idx(tpl_1(reqs[i]), history)][0] >= 2'b10) && tpl_2(reqs[i]);
            predicted_bhrs[i+1] <= history;

            dbg_print(PRED, $format("Predicting: %h ", pc_to_pht_idx(tpl_1(reqs[i]), history), fshow(reqs[i])));

            // update values for BHR canonicalization
            if(!predicted_results[i]) begin
                predicted_count[i] <= predicted_count[i] + 1;
                predicted_results[i] <= taken;
                outbound_results[i] <= taken;
            end
        endrule
    end

    // return history such that it can be tracked in ROB and restored if mispredicted
    Vector#(IFUINST, Wire#(Bit#(BITS_BHR))) outbound_history <- replicateM(mkWire());
    for(Integer i = 0; i < valueOf(IFUINST); i=i+1) begin
        rule progress;
            outbound_history[i] <= predicted_bhrs[i+2];
        endrule
    end

    // prediction request/response interface
    Vector#(IFUINST, Server#(Tuple2#(Bit#(PCLEN), Bool), Prediction)) pred_ifc = ?;
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        pred_ifc[i] = (interface Server;
            interface Put request;
                method Action put(Tuple2#(Bit#(PCLEN), Bool) in);
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

    // input for training data
    interface Put train;
        method Action put(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)) in);
            trains.enq(in);
        endmethod
    endinterface

    method Action current_thread(UInt#(thread_id_t) thread_id) = thread_id_w._write(thread_id);

endmodule

endpackage