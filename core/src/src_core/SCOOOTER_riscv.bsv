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
    let arith3 <- mkArith();
    let arith4 <- mkArith();
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

    let fu_vec = vec(arith, branch, mem, arith2, arith3, arith4);
    function Maybe#(Result) get_result(FunctionalUnitIFC fu) = fu.get();
    let result_bus_vec = Vector::map(get_result, fu_vec);

    RobIFC rob <- mkReorderBuffer();

    CommitIFC commit <- mkCommit();

    RegFileIFC regfile_arch <- mkRegFile();

    RegFileEvoIFC regfile_evo <- mkRegFileEvo();

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
    ReservationStationIFC#(6) rs_alu <- mkReservationStationALU6();
    ReservationStationIFC#(6) rs_alu2 <- mkReservationStationALU6();
    ReservationStationIFC#(6) rs_alu3 <- mkReservationStationALU6();
    ReservationStationIFC#(6) rs_alu4 <- mkReservationStationALU6();
    //MEM unit
    ReservationStationIFC#(6) rs_mem <- mkReservationStationMEM6();
    //branch unit
    ReservationStationIFC#(6) rs_br <- mkReservationStationBR6();

    rule propagate_result_bus;
        rs_alu.result_bus(result_bus_vec);
        rs_alu2.result_bus(result_bus_vec);
        rs_alu3.result_bus(result_bus_vec);
        rs_alu4.result_bus(result_bus_vec);
        rs_mem.result_bus(result_bus_vec);
        rs_br.result_bus(result_bus_vec);
        regfile_evo.result_bus(result_bus_vec);
        rob.result_bus(result_bus_vec);
    endrule

    rule rs_to_arith;
        let i <- rs_alu.get();
        arith.put(i);
    endrule

    rule rs_to_arith2;
        let i <- rs_alu2.get();
        arith2.put(i);
    endrule

    rule rs_to_arith3;
        let i <- rs_alu3.get();
        arith3.put(i);
    endrule

    rule rs_to_arith4;
        let i <- rs_alu4.get();
        arith4.put(i);
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

    Vector#(NUM_RS, ReservationStationIFC#(6)) rs_vec = vec(rs_alu, rs_mem, rs_br, rs_alu2, rs_alu3, rs_alu4);

    let issue <- mkIssue();


    function Bool get_rdy(ReservationStationIFC#(e) rs) = rs.free();
    function ExecUnitTag get_op_type(ReservationStationIFC#(e) rs) = rs.unit_type();

    rule connect_rs_issue;
        let rdy_inst_vec = Vector::map(get_rdy   , rs_vec);
        issue.rs_ready(rdy_inst_vec);
    endrule

    rule connect_rs_issue2;
        let type_vec = Vector::map(get_op_type   , rs_vec);
        issue.rs_type(type_vec);
    endrule

    rule connect_rs_issue3;
        let issue_bus = issue.get_issue();
        for(Integer i = 0; i < valueOf(NUM_RS); i = i+1) begin
            if(issue_bus[i] matches tagged Valid .inst)
                rs_vec[i].put(inst);
        end
    endrule

    Wire#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) evo_wire <- mkWire();
    rule issue_to_rf_evo;
        let req = issue.request_addrs();
        let resp = regfile_evo.read_regs(req);
        evo_wire <= resp;
    endrule

    rule issue_to_rf_evo2;
        let resp = evo_wire;
        issue.response_regs(resp);
    endrule

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

    rule connect_rob_issue;
        issue.rob_free(rob.free());
        issue.rob_current_idx(rob.current_idx());
    endrule

    rule connect_rob_issue2;
        let req = issue.get_reservation();
        rob.reserve(tpl_1(req), tpl_2(req));
    endrule

    function RegReservation to_regres(RADDR addr, UInt#(TLog#(ROBDEPTH)) tag) = RegReservation {addr:addr, tag:tag};
    rule connect_issue_evo;
        let tags_out = issue.set_tags();
        let tags = Vector::map(tpl_2, tpl_1(tags_out));
        let raddrs = Vector::map(tpl_1, tpl_1(tags_out));
        let epochs = Vector::map(tpl_3, tpl_1(tags_out));
        let count = tpl_2(tags_out);

        let reservations = Vector::map(uncurry(to_regres), Vector::zip(raddrs, tags));

        regfile_evo.set_tags(reservations, epochs, count);
    endrule

    interface ifu_axi = ifu.ifu_axi;

endmodule

endpackage
