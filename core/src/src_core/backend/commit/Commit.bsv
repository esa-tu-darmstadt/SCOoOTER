package Commit;

import Debug::*;
import Types::*;
import Vector::*;
import Inst_Types::*;
import Interfaces::*;
import FIFO::*;
import SpecialFIFOs::*;
import BlueAXI::*;
import Connectable::*;

(* synthesize *)
module mkCommit(CommitIFC) provisos(
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t)
);

AXI4_Master_Wr#(XLEN, XLEN, 0, 0) axi <- mkAXI4_Master_Wr(1, 1, 1, False);
rule discard_resp;
    let r <- axi4_write_response(axi);
endrule

FIFO#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) out_buffer <- mkPipelineFIFO();

Reg#(UInt#(XLEN)) epoch <- mkReg(0);

Wire#(Bit#(XLEN)) redirect_pc_w <- mkWire();

function Bool check_entry_for_mem_access(RobEntry entry) = (entry.mem_wr matches tagged Valid .v ? True : False);
method ActionValue#(UInt#(issuewidth_log_t)) consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(issuewidth_log_t) count);
    actionvalue
        Vector#(ISSUEWIDTH, Maybe#(RegWrite)) temp_requests = replicate(tagged Invalid);

        Bool done = False;

        //only for bodge
        UInt#(issuewidth_log_t) count_committed = count;

        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            if(instructions[i].epoch == epoch) begin
                // write registers
                if(fromInteger(i) < count &&& 
                   instructions[i].result matches tagged Result .r &&& 
                   !done) begin
                    dbg_print(Commit, $format(fshow(instructions[i])));
                    temp_requests[i] = tagged Valid RegWrite {addr: instructions[i].destination, data: r};
                end

                // check branch
                if(fromInteger(i) < count && instructions[i].next_pc != instructions[i].pred_pc && !done) begin
                    epoch <= epoch + 1;
                    // generate mispredict signal for IFU
                    redirect_pc_w <= instructions[i].next_pc;
                    done = True;
                    count_committed = fromInteger(i);
                end
            end

            
        end

        //Bodged Memory Write (may skip over writes but sufficient for TB)
        let first_mem_req = Vector::findIndex(check_entry_for_mem_access, instructions);
        if(first_mem_req matches tagged Valid .first_mem_idx &&&
            first_mem_idx < count_committed &&&
            instructions[first_mem_idx].epoch == epoch) begin
                axi4_write_data_single(axi, pack(instructions[first_mem_idx].mem_wr.Valid.mem_addr), instructions[first_mem_idx].mem_wr.Valid.data, 'b1111);
            end


        out_buffer.enq(temp_requests);

        return count;
    endactionvalue
endmethod

method Bit#(XLEN) redirect_pc();
    return redirect_pc_w;
endmethod

method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    actionvalue
        out_buffer.deq();
        return out_buffer.first();
    endactionvalue
endmethod

interface dmem_axi = axi.fab;

endmodule

endpackage