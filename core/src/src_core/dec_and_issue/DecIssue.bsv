package DecIssue;

import Decode :: *;
import MIMO :: *;
import Types :: *;
import Inst_Types :: *;
import Vector :: *;
import ListN :: *; // TODO: Substitute Vector with ListN where sensible
import Interfaces :: *;
import ReservationStation :: *;
import List :: *;

module mkDecIssue#(Vector#(rs_count, ReservationStationIFC#(t, e)) rs_vec)(DecAndIssueIFC) provisos(
    );

    Wire#(MIMO::LUInt#(ISSUEWIDTH)) remove_w <- mkDWire(0);
    RWire#(Bit#(XLEN)) redirect_pc_w <- mkRWire();

    function UInt#(t) get_free(ReservationStationIFC#(t, e) rs);
        return rs.free;
    endfunction

     function Bool check_rs(OpCode opc, Tuple2#(ReservationStationIFC#(t, e), UInt#(t)) rs_info);
        // if RS is full, we cannot enqueue
        // if not full and opc match, success
        if (tpl_2(rs_info) != 0 && List::elem(opc, tpl_1(rs_info).supported_opc)) return True;
        //else no success
        else return False;
    endfunction

    method Action put(Vector#(ISSUEWIDTH, InstructionPredecode) instructions, MIMO::LUInt#(ISSUEWIDTH) amount);

        // counter and release variable
        MIMO::LUInt#(ISSUEWIDTH) i = 0, rem = 0; //TODO: rebuild type using provisos
        Bool issue_done = False;

        // get free space in all RS
        Vector#(rs_count, UInt#(t)) rs_free = Vector::map(get_free, rs_vec);

        // placeholder for instructions to RS
        Vector#(rs_count, Vector#(ISSUEWIDTH, Instruction)) rs_enq = ?;

        // inst to enq
        Vector#(rs_count, MIMO::LUInt#(ISSUEWIDTH)) rs_enqctr = Vector::replicate(0);
        let decoded_inst_v = Vector::map(decode, instructions);

        // TODO: make this loop less ugly
        // defer instructions one by one
        while(i < amount && i < fromInteger(valueOf(ISSUEWIDTH)) && !issue_done) begin
            let decoded_inst = decoded_inst_v[i];

            // check if a free reservationstation is available
            let idx = findIndex(check_rs(decoded_inst.opc), Vector::zip(rs_vec, rs_free));
            
            // if it is available:
            if (isValid(idx)) begin
                let idxv = fromMaybe(?, idx);
                //enqueue
                rs_enq[idxv][rs_enqctr[idxv]] = decoded_inst;
                //update counters
                rs_free[idxv] = rs_free[idxv] - 1;
                rs_enqctr[idxv] = rs_enqctr[idxv] + 1;
                rem=rem+1;
            end else issue_done = True;

            i=i+1;
        end

        //TODO: check for 0 not really needed if RS written correctly
        for (Integer j=0; j<valueOf(rs_count); j=j+1)
            if(rs_enqctr[j] != 0) rs_vec[j].put(rs_enq[j], rs_enqctr[j]);


        remove_w <= rem;

    endmethod

    method MIMO::LUInt#(ISSUEWIDTH) remove;
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