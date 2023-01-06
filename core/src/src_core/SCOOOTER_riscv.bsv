package SCOOOTER_riscv;

import BlueAXI::*;
import Interfaces::*;
import Fetch::*;
import Types::*;
import ReservationStation::*;
import BuildVector::*;
import Vector::*;
import List::*;
import Inst_Types::*;
import BuildList::*;
import Arith::*;
import ReorderBuffer :: *;
import Debug::*;
import Commit::*;
import RegFileArch::*;
import RegFileEvo::*;
import Decode::*;
import Issue::*;
import Branch::*;
import Mem::*;

(* synthesize *)
module mkSCOOOTER_riscv(Top#(ifuwidth)) provisos(
        Mul#(XLEN, IFUINST, ifuwidth),
        Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
        Log#(issuewidth_pad_t, issuewidth_log_t)
    );

    let ifu <- mkFetch();

    let decode <- mkDecode();

    let arith <- mkArith();
    let arith2 <- mkArith();
    let branch <- mkBranch();
    let mem <- mkMem();

    rule fetch_to_decode;
        let inst = ifu.first();
        let cnt = ifu.count();
        ifu.deq();

        let instructions = Vector::map(tpl_1, inst);
        let pcs = Vector::map(tpl_2, inst);
        let epochs = Vector::map(tpl_3, inst);

        decode.put(cnt, instructions, pcs, epochs);
    endrule

    let fu_vec = vec(arith, branch, mem);
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
    ReservationStationIFC#(6) rs_alu <- mkReservationStation(ALU, result_bus_vec);
    ReservationStationIFC#(6) rs_alu2 <- mkReservationStation(ALU, result_bus_vec);
    //MEM unit
    ReservationStationIFC#(6) rs_mem <- mkReservationStation(LS, result_bus_vec);
    //branch unit
    ReservationStationIFC#(6) rs_br <- mkReservationStation(BR, result_bus_vec);

    rule rs_to_arith;
        let i <- rs_alu.get();
        arith.put(i);
    endrule

    rule rs_to_arith2;
        let i <- rs_alu2.get();
        arith2.put(i);
    endrule

    rule rs_to_br;
        let i <- rs_br.get();
        branch.put(i);
    endrule

    rule rs_to_mem;
        let i <- rs_mem.get();
        mem.put(i);
    endrule

    rule print_res;
        dbg_print(Top, $format(fshow(result_bus_vec)));
    endrule

    let rs_vec = vec(rs_alu, rs_mem, rs_br);

    let issue <- mkIssue(rs_vec, rob, regfile_evo);

    rule issue_to_dec;
        let data = decode.first;
        issue.put(data, ( decode.count > fromInteger(valueOf(ISSUEWIDTH)) ? fromInteger(valueOf(ISSUEWIDTH)) : truncate(decode.count) ));
    endrule

    rule issue_to_dec_wipe;
        let count = issue.remove;
        decode.deq(count);
    endrule

    rule flush_prints;
        $fflush();
    endrule

    rule commit_to_fetch;
        let new_pc = commit.redirect_pc();
        regfile_evo.flush();
        ifu.redirect(new_pc);
    endrule

    interface ifu_axi = ifu.ifu_axi;

endmodule

endpackage
