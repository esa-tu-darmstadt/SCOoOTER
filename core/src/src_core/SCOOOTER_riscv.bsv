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
import BuildList :: *;
import Arith :: *;
import ReorderBuffer :: *;
import Debug::*;
import Commit::*;
import RegFileArch::*;
import RegFileEvo::*;

(* synthesize *)
module mkSCOOOTER_riscv(Top#(ifuwidth)) provisos(
        Mul#(XLEN, IFUINST, ifuwidth),
        Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
        Log#(issuewidth_pad_t, issuewidth_log_t)
    );

    IFU#(ifuwidth, 12) ifu <- mkFetch();

    let arith <- mkArith();

    let fu_vec = vec(arith);
    function Maybe#(Result) get_result(FunctionalUnitIFC fu) = fu.get();
    let result_bus_vec = Vector::map(get_result, fu_vec);

    RobIFC rob <- mkReorderBuffer(result_bus_vec);

    CommitIFC commit <- mkCommit();

    RegFileIFC regfile_arch <- mkRegFile();

    RegFileEvoIFC regfile_evo <- mkRegFileEvo(result_bus_vec);

    rule connect_commit_regs;
        let requests <- commit.get_write_requests();
        regfile_arch.write(requests);
    endrule

    rule connect_regfiles;
        regfile_evo.committed_state(regfile_arch.values());
    endrule

    Wire#(UInt#(issuewidth_log_t)) deq_rob_wire <- mkDWire(0);
    rule connect_rob_commit;
        let deq <- commit.consume_instructions(rob.get(), rob.available());
        deq_rob_wire <= deq;
    endrule

    rule deq_rob_entries;
        rob.complete_instructions(deq_rob_wire);
    endrule

    // ALU unit
    ReservationStationIFC#(8,6) rs_alu <- mkReservationStation(list(LUI, AUIPC, OP, OPIMM), ALU);
    //MEM unit
    ReservationStationIFC#(8,6) rs_mem <- mkReservationStation(list(LOAD, STORE, AMO, MISCMEM),LS); // if f ext: LOAD_FP, STORE_FP
    //branch unit
    ReservationStationIFC#(8,6) rs_br <- mkReservationStation(list(BRANCH, JALR, JAL),BR); // if f ext: LOAD_FP, STORE_FP

    rule rs_to_arith;
        let i <- rs_alu.get();
        arith.put(i);
    endrule

    rule print_res;
        dbg_print(Top, $format(fshow(result_bus_vec)));
    endrule

    Vector#(3, ReservationStationIFC#(8,6)) rs_vec = vec(rs_alu, rs_mem, rs_br);

    let dec_issue <- mkDecIssue(rs_vec, rob);

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

    rule flush_prints;
        $fflush();
    endrule

    interface ifu_axi = ifu.ifu_axi;

endmodule

endpackage
