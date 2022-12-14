package SCOOOTER_riscv;

import BlueAXI :: *;
import Interfaces :: *;
import Fetch :: *;
import Types :: *;
import DecIssue :: *;
import ReservationStation :: *;
import BuildVector :: *;
import Vector :: *;
import List :: *;
import Inst_Types :: *;

module mkSCOOOTER_riscv(Top#(ifuwidth)) provisos(
        Mul#(XLEN, IFUINST, ifuwidth)
    );

    let ifu <- mkFetch();

    // ALU unit
    ReservationStationIFC#(8,6) rs_alu <- mkReservationStation(toList(vec(LUI, AUIPC, OP, OPIMM)));
    //MEM unit
    ReservationStationIFC#(8,6) rs_mem <- mkReservationStation(toList(vec(LOAD, STORE, AMO, MISCMEM))); // if f ext: LOAD_FP, STORE_FP
    //branch unit
    ReservationStationIFC#(8,6) rs_br <- mkReservationStation(toList(vec(BRANCH, JALR, JAL))); // if f ext: LOAD_FP, STORE_FP

    let rs_list = vec(rs_alu, rs_mem, rs_br);

    let dec_issue <- mkDecIssue(rs_list);

    rule ifu_to_dec;
        let data = ifu.first;
        dec_issue.put(data, ( ifu.count > fromInteger(valueOf(ISSUEWIDTH)) ? fromInteger(valueOf(ISSUEWIDTH)) : truncate(ifu.count) ));
    endrule

    rule ifu_to_dec_wipe;
        let count = dec_issue.remove;
        ifu.deq(count);
    endrule

    rule dec_to_ifu;
        let new_pc = dec_issue.redirect_pc;
        ifu.redirect(new_pc);
    endrule

    interface ifu_axi = ifu.ifu_axi;

endmodule

endpackage
