package DecIssue;

import Decode::*;
import MIMO::*;
import Types::*;
import Inst_Types::*;
import Vector::*;
import ListN::*; // TODO: Substitute Vector with ListN where sensible
import Interfaces::*;
import ReservationStation::*;
import List::*;
import FIFO::*;
import SpecialFIFOs::*;
import TestFunctions::*;
import Debug::*;

module mkDecIssue#(Vector#(rs_count, ReservationStationIFC#(rs_addr_width, e)) rs_vec, RobIFC rob)(DecAndIssueIFC) provisos(
    Add#(ROBDEPTH, 1, r_a),
    Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),

    Add#(ROBDEPTH, 1, rob_pad_t),
    Log#(rob_pad_t, rob_log_t),
    Add#(__b, 1, rob_log_t),
    Log#(ROBDEPTH, rob_addr_t),

    Add#(0, 4, rob_addr_t),
    Add#(0, 5, rob_log_t),

    Add#(__a, 1, rs_addr_width)
    );

    Wire#(UInt#(issuewidth_log_t)) remove_w <- mkDWire(0);
    RWire#(Bit#(XLEN)) redirect_pc_w <- mkRWire();

    function UInt#(rs_addr_width) get_free(ReservationStationIFC#(rs_addr_width, e) rs);
        return rs.free;
    endfunction

    function Integer find_rs(Vector#(rs_count, ReservationStationIFC#(rs_addr_width, e)) rs_vec, Instruction inst);
        Integer result = ?;
        for(Integer i = 0; i<valueOf(rs_count); i=i+1)
            if(inst.eut == rs_vec[i].unit_type) result = i;
        return result;
    endfunction

    function Bool check_rs(OpCode opc, Tuple2#(ReservationStationIFC#(rs_addr_width, e), UInt#(t)) rs_info);
        // if RS is full, we cannot enqueue
        // if not full and opc match, success
        if (tpl_2(rs_info) != 0 && List::elem(opc, tpl_1(rs_info).supported_opc)) return True;
        //else no success
        else return False;
    endfunction

    function RobEntry map_to_rob_entry(tpl inst_and_idx) provisos (
        Has_tpl_1#(tpl, Inst_Types::Instruction),
        Has_tpl_2#(tpl, UInt#(rob_addr_t))
    );
        Instruction inst = tpl_1(inst_and_idx);
        UInt#(rob_addr_t) idx = tpl_2(inst_and_idx);

        return RobEntry {
            pc : inst.pc,
            destination : inst.rd.Raddr,
            result : (isValid(inst.exception) ?
                      tagged Except fromMaybe(?, inst.exception) :
                      tagged Tag idx)
        };
    endfunction

    function Instruction tag_instruction(tpl inst_and_idx) provisos (
        Has_tpl_1#(tpl, Inst_Types::Instruction),
        Has_tpl_2#(tpl, UInt#(rob_addr_t))
    );
        Inst_Types::Instruction inst = tpl_1(inst_and_idx);
        inst.tag = tpl_2(inst_and_idx);
        return inst;
    endfunction

    function UInt#(rob_addr_t) generate_tag(UInt#(rob_addr_t) base, Integer i);
        return base + fromInteger(i);
    endfunction

    //buffer for incoming inst
    FIFO#(Vector#(rs_count, Vector#(ISSUEWIDTH, Instruction))) out_inst_f <- mkPipelineFIFO();
    FIFO#(Vector#(rs_count, UInt#(issuewidth_log_t))) out_cnt_f <- mkPipelineFIFO();

    rule output_instructions;
        Vector#(rs_count, Vector#(ISSUEWIDTH, Instruction)) rs_enq = out_inst_f.first(); out_inst_f.deq();
        Vector#(rs_count, UInt#(issuewidth_log_t)) rs_enqctr = out_cnt_f.first(); out_cnt_f.deq();
        //TODO: check for 0 not really needed if RS written correctly
        for (Integer j=0; j<valueOf(rs_count); j=j+1)
            if(rs_enqctr[j] != 0) rs_vec[j].put(rs_enq[j], rs_enqctr[j]);
    endrule

    method Action put(Vector#(ISSUEWIDTH, InstructionPredecode) instructions, UInt#(issuewidth_log_t) amount);

        // counter and release variable
        UInt#(issuewidth_log_t) rem = 0; //TODO: rebuild type using provisos
        Bool issue_done = False;

        // get free space in all RS
        Vector#(rs_count, UInt#(rs_addr_width)) rs_free = Vector::map(get_free, rs_vec);

        // placeholder for instructions to RS
        Vector#(rs_count, Vector#(ISSUEWIDTH, Instruction)) rs_enq = ?;

        // inst to enq
        Vector#(rs_count, UInt#(issuewidth_log_t)) rs_enqctr = Vector::replicate(0);

        UInt#(rob_addr_t) rob_idx = rob.current_idx;
        UInt#(rob_log_t) rob_free = rob.free;

        let rob_entry_idx_v = Vector::genWith(generate_tag(rob_idx));

        // decode all inst
        let decoded_inst_v = Vector::map(squash_operands, Vector::map(decode, instructions));
        decoded_inst_v = Vector::map(tag_instruction, Vector::zip(decoded_inst_v, rob_entry_idx_v));

        dbg_print(Decode, $format("instructions: ", fshow(decoded_inst_v)));

        // find fitting execution unit per inst
        let rs_index_v = Vector::map(find_rs(rs_vec), decoded_inst_v);

        let rob_entry_v = Vector::map(map_to_rob_entry, Vector::zip(decoded_inst_v, rob_entry_idx_v));
        amount = (extend(amount) < rob_free ? amount : truncate(rob_free));
        rob.reserve(rob_entry_v, amount);


        //special issue logic for width of 1
        if(valueOf(ISSUEWIDTH) == 1 && amount == 1) begin
            let idx = rs_index_v[0];
            if(rs_free[idx] > 0) begin
                
                rs_enqctr[idx] = 1;
                rs_enq[idx][0] = decoded_inst_v[0];
                rem=rem+1;
            end

        end else begin

            //issue logic via tag (less flexible but faster)
            for(Integer i = 0; i < valueOf(ISSUEWIDTH) && fromInteger(i) < amount; i=i+1) begin
                let idx = rs_index_v[i];

                if(rs_free[idx] > extend(rs_enqctr[idx]) && !issue_done) begin
                    rs_enq[idx][rs_enqctr[idx]] = decoded_inst_v[i];
                    //update counters
                    rs_enqctr[idx] = rs_enqctr[idx] + 1;
                    rem=rem+1;
                end else issue_done = True;
        end

        //issue logic from list
        /*for(Integer i = 0; i < valueOf(ISSUEWIDTH) && fromInteger(i) < amount && !issue_done; i=i+1) begin
            let idx = findIndex(check_rs(decoded_inst_v[i].opc), Vector::zip(rs_vec, rs_free));

            // if it is available:
            if (isValid(idx)) begin
                let idxv = fromMaybe(?, idx);
                //enqueue
                rs_enq[idxv][rs_enqctr[idxv]] = decoded_inst_v[i];
                //update counters
                rs_free[idxv] = rs_free[idxv] - 1;
                rs_enqctr[idxv] = rs_enqctr[idxv] + 1;
                rem=rem+1;
            end else issue_done = True;
        end*/

        end

        out_inst_f.enq(rs_enq);
        out_cnt_f.enq(rs_enqctr);

        remove_w <= rem;

    endmethod

    method UInt#(issuewidth_log_t) remove;
        return remove_w;
    endmethod

    /*if(decoded_inst.opc == JAL) begin
                issue_done = True;
                redirect_pc_w.wset('h14);
            end*/
    method Bit#(XLEN) redirect_pc if (isValid(redirect_pc_w.wget));
        return fromMaybe(?, redirect_pc_w.wget);
    endmethod


endmodule

endpackage