package BTB;

/*
  This is the Branch Target Buffer. The BTB stores branch targets
  which can be retrieved during speculation.
*/

import Vector::*;
import Interfaces::*;
import Types::*;
import Inst_Types::*;
import Config::*;
import GetPut::*;
import Debug::*;
import FIFO::*;
import SpecialFIFOs::*;
import ClientServer::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkBTB(BTBIfc) provisos (
    Add#(2, inst_addr_t, XLEN), // as we do not support compressed, we can strip two bits off the addr
    Add#(BITS_BTB, bits_tag_t, inst_addr_t), // calculate tag size dependant on the bits used for indexing
    Log#(entries_t, BITS_BTB), // calculate the amount of entries necessary for the tag bits
    Add#(0, TExp#(BITS_BTB), entries_t), // TODO: ugly but the compiler needs this
    // create types for instruction amount trackung
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);
    // create internal storage
    Vector#(entries_t, Reg#(Bit#(XLEN))) targets <- replicateM(mkRegU());
    Vector#(entries_t, Reg#(Bit#(bits_tag_t))) tags <- replicateM(mkRegU());

    // request / response FIFOs
    FIFO#(Bit#(XLEN)) requested_prediction <- mkPipelineFIFO();
    FIFO#(Vector#(IFUINST, Maybe#(Bit#(XLEN)))) produced_prediction <- mkBypassFIFO();

    // debug rule to show debuging info
    rule show_buffer;
        dbg_print(BTB, $format("-----------------"));
        for(Integer i = 0; i < valueOf(entries_t); i = i+1) begin
            Bit#(BITS_BTB) tag_ext = fromInteger(i);
            dbg_print(BTB, $format(fshow({tags[i], tag_ext, 2'b00}), " ", fshow(targets[i])));
        end
    endrule

    // produce predictions based on the internally stored information
    rule calculate;
        Bit#(inst_addr_t) base = truncate(requested_prediction.first()>>2);
        requested_prediction.deq();

        Vector#(IFUINST, Maybe#(Bit#(XLEN))) temp = replicate(tagged Invalid);
        for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
            Bit#(BITS_BTB) idx = truncate(base+fromInteger(i));
            Bit#(bits_tag_t) tag = truncateLSB(base+fromInteger(i));

            if(tags[idx] == tag) temp[i] = tagged Valid targets[idx];
        end

        produced_prediction.enq(temp);
    endrule

    // train the predictor
    // if a branch was evaluated to be taken, store target
    interface Put train;
        method Action put(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(issuewidth_log_t)) in);
            Vector#(entries_t, Bit#(XLEN)) local_targets = Vector::readVReg(targets);
            Vector#(entries_t, Bit#(bits_tag_t)) local_tags = Vector::readVReg(tags);

        
            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i = i+1) begin
                if (fromInteger(i) < tpl_2(in)) begin
                    let train = tpl_1(in)[i];
                    if (train matches tagged Valid .tv &&& tv.taken) begin
                        Bit#(inst_addr_t) aligned_addr = truncate(tv.pc>>2);
                        Bit#(BITS_BTB) idx = truncate(aligned_addr);
                        Bit#(bits_tag_t) tag = truncateLSB(aligned_addr);

                        local_targets[idx] = tv.target;
                        local_tags[idx] = tag;
                    end
                end
            end

            Vector::writeVReg(targets, local_targets);
            Vector::writeVReg(tags, local_tags);
        endmethod
    endinterface

    // interface for prediction
    interface Server predict;
        interface Put request = toPut(requested_prediction);
        interface Get response = toGet(produced_prediction);
    endinterface
endmodule

endpackage