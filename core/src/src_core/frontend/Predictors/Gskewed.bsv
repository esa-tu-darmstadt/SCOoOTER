package Gskewed;

/*
  This is the GSkewed direction predictor
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
import BuildVector::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkGskewed(PredIfc) provisos (
    // TODO: this is ugly
    Add#(0, TExp#(BITS_PHT), entries_t),
    // create types for instruction amount tracking
    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),
    // we want to XOR the history with the upper part of the PC
    // as the lower PC bits offer more entropy
    Log#(NUM_THREADS, thread_id_t)
);
    // internal storage
    Vector#(entries_t, Ehr#(ISSUEWIDTH, UInt#(2))) pht1 <- replicateM(mkEhr(0));
    Vector#(entries_t, Ehr#(ISSUEWIDTH, UInt#(2))) pht2 <- replicateM(mkEhr(0));
    Vector#(entries_t, Ehr#(ISSUEWIDTH, UInt#(2))) pht3 <- replicateM(mkEhr(0));
    // branch history register
    Vector#(NUM_THREADS, Array#(Reg#(Bit#(BITS_BHR)))) bhr <- replicateM(mkCReg(2, 0));

    Wire#(UInt#(thread_id_t)) thread_id_w <- mkBypassWire();
    
    // hashing function for GSKEWED combination functions
    function Bit#(BITS_PHT) hash_fwd(Bit#(BITS_PHT) val) = {val[0]^val[valueOf(BITS_PHT)-1], truncate(val >> 1)};
    function Bit#(BITS_PHT) hash_bwd(Bit#(BITS_PHT) val) = {truncate(val), val[0]^val[valueOf(BITS_PHT)-1]};

    // three different PC and BHR combinatory functions
    function Bit#(BITS_PHT) hash1(Bit#(XLEN) addr, Bit#(BITS_BHR) hist) = hash_bwd( truncate(addr>>2) )^hash_fwd({hist,0})^{hist,0};
    function Bit#(BITS_PHT) hash2(Bit#(XLEN) addr, Bit#(BITS_BHR) hist) = hash_bwd( truncate(addr>>2) )^hash_fwd({hist,0})^(truncate(addr>>2));
    function Bit#(BITS_PHT) hash3(Bit#(XLEN) addr, Bit#(BITS_BHR) hist) = hash_fwd( truncate(addr>>2) )^hash_bwd({hist,0})^{hist,0};

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

    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
    rule train_predictors;
        let in = trains.first();
        
            if(in[i] matches tagged Valid .train &&& train.branch) begin

                let idx1 = hash1(train.pc, train.history);
                let idx2 = hash2(train.pc, train.history);
                let idx3 = hash3(train.pc, train.history);

                if (train.taken) begin

                    if (pht1[idx1][i] != 'b11) pht1[idx1][i] <= pht1[idx1][i] + 1;
                    if (pht2[idx2][i] != 'b11) pht2[idx2][i] <= pht2[idx2][i] + 1;
                    if (pht3[idx3][i] != 'b11) pht3[idx3][i] <= pht3[idx3][i] + 1;
                end else begin


                    if (pht1[idx1][i] != 'b00) pht1[idx1][i] <= pht1[idx1][i] - 1;
                    if (pht2[idx2][i] != 'b00) pht2[idx2][i] <= pht2[idx2][i] - 1;
                    if (pht3[idx3][i] != 'b00) pht3[idx3][i] <= pht3[idx3][i] - 1;
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
    Vector#(IFUINST, Wire#(Tuple2#(Bit#(XLEN), Bool))) reqs <- replicateM(mkWire());
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        rule generate_prediction;
            // all previous predictions must be untaken for this one to matter
            Bit#(BITS_BHR) history = bhr[thread_id_w][1] << predicted_count[i];
            // check PHT for prediction
            let idx1 = hash1(tpl_1(reqs[i]), history);
            let idx2 = hash2(tpl_1(reqs[i]), history);
            let idx3 = hash3(tpl_1(reqs[i]), history);

            Vector#(3, Bool) res = vec(
                pht1[idx1][i] >= 'b10,
                pht2[idx2][i] >= 'b10,
                pht3[idx3][i] >= 'b10
            );


            Bool taken = (Vector::countElem(True, res) >= 2) && tpl_2(reqs[i]);
            predicted_bhrs[i+1] <= history;

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
    Vector#(IFUINST, Server#(Tuple2#(Bit#(XLEN), Bool), Prediction)) pred_ifc = ?;
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        pred_ifc[i] = (interface Server;
            interface Put request;
                method Action put(Tuple2#(Bit#(XLEN), Bool) in);
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