package BTB;

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

(* synthesize *)
module mkBTB(BTBIfc) provisos (
    Add#(2, inst_addr_t, XLEN),
    Add#(BITS_BTB, bits_tag_t, inst_addr_t),
    Log#(entries_t, BITS_BTB),
    // TODO: this is ugly
    Add#(0, TExp#(BITS_BTB), entries_t),

    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);
    Vector#(entries_t, Reg#(Bit#(XLEN))) targets <- replicateM(mkRegU());
    Vector#(entries_t, Reg#(Bit#(bits_tag_t))) tags <- replicateM(mkRegU());

    FIFO#(Bit#(XLEN)) requested_prediction <- mkPipelineFIFO();
    FIFO#(Vector#(IFUINST, Maybe#(Bit#(XLEN)))) produced_prediction <- mkBypassFIFO();

    rule show_buffer;
        dbg_print(BTB, $format("-----------------"));
        for(Integer i = 0; i < valueOf(entries_t); i = i+1) begin
            Bit#(BITS_BTB) tag_ext = fromInteger(i);
            dbg_print(BTB, $format(fshow({tags[i], tag_ext, 2'b00}), " ", fshow(targets[i])));
        end
    endrule

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
                    /*if (train matches tagged Valid .tv &&& !tv.taken) begin
                        Bit#(inst_addr_t) aligned_addr = truncate(tv.pc>>2);
                        Bit#(BITS_BTB) idx = truncate(aligned_addr);
                        Bit#(bits_tag_t) tag = truncateLSB(aligned_addr);

                        if(aligned_addr == {local_tags[idx], idx}) begin
                            local_targets[idx] = -1;
                            local_tags[idx] = -1;
                        end
                    end*/
                end
            end

            Vector::writeVReg(targets, local_targets);
            Vector::writeVReg(tags, local_tags);
        endmethod
    endinterface

    interface Server predict;
        interface Put request = toPut(requested_prediction);
        interface Get response = toGet(produced_prediction);
    endinterface
endmodule

endpackage