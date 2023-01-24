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
import GetPut::*;
import Connectable :: *;
import MulDiv::*;
import MemoryArbiter::*;
import StoreBuffer::*;

(* synthesize *)
module mkSCOOOTER_riscv(Top) provisos(
        Mul#(XLEN, IFUINST, ifuwidth),
        Add#(ISSUEWIDTH, 1, issuewidth_pad_t),
        Log#(issuewidth_pad_t, issuewidth_log_t)
    );

    let ifu <- mkFetch();

    let decode <- mkDecode();

    let arith <- mkArith();
    let arith2 <- mkArith();
    let arith3 <- mkArith();
    let md <- mkMulDiv();
    let branch <- mkBranch();
    let mem <- mkMem();

    let store_buf <- mkStoreBuffer();

    mkConnection(ifu.instructions, decode.instructions);

    let mem_arbiter <- mkMemoryArbiter();

    mkConnection(store_buf.write, mem_arbiter.write);

    let fu_vec = vec(arith, branch, mem.fu, arith2, arith3, md);
    function Maybe#(Result) get_result(FunctionalUnitIFC fu) = fu.get();
    let result_bus_vec = Vector::map(get_result, fu_vec);

    RobIFC rob <- mkReorderBuffer();

    CommitIFC commit <- mkCommit();

    mkConnection(commit.memory_writes, store_buf.memory_writes);

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
    ReservationStationIFC#(6) rs_md <- mkReservationStationMULDIV6();
    //MEM unit
    ReservationStationIFC#(6) rs_mem <- mkReservationStationMEM6();
    //branch unit
    ReservationStationIFC#(6) rs_br <- mkReservationStationBR6();

    rule propagate_result_bus;
        rs_alu.result_bus(result_bus_vec);
        rs_alu2.result_bus(result_bus_vec);
        rs_alu3.result_bus(result_bus_vec);
        rs_md.result_bus(result_bus_vec);
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

    rule rs_to_md;
        let i <- rs_md.get();
        md.put(i);
    endrule

    rule rs_to_br;
        let i <- rs_br.get();
        branch.put(i);
    endrule

    rule rs_to_mem;
        let i <- rs_mem.get();
        mem.fu.put(i);
    endrule

    mkConnection(rob.check_pending_memory, mem.check_rob);
    mkConnection(store_buf.forward, mem.check_store_buffer);
    mkConnection(mem_arbiter.read, mem.read);

    rule print_res;
        dbg_print(Top, $format(fshow(result_bus_vec)));
    endrule

    Vector#(NUM_RS, ReservationStationIFC#(6)) rs_vec = vec(rs_alu, rs_mem, rs_br, rs_alu2, rs_alu3, rs_md);

    let issue <- mkIssue();


    function Bool get_rdy(ReservationStationIFC#(e) rs) = rs.in.can_insert();
    function ExecUnitTag get_op_type(ReservationStationIFC#(e) rs) = rs.unit_type();

    rule connect_rs_issue;
        let rdy_inst_vec = Vector::map(get_rdy, rs_vec);
        issue.rs_ready(rdy_inst_vec);
    endrule

    rule connect_rs_issue2;
        let type_vec = Vector::map(get_op_type, rs_vec);
        issue.rs_type(type_vec);
    endrule

    rule connect_rs_issue3;
        let issue_bus = issue.get_issue();
        for(Integer i = 0; i < valueOf(NUM_RS); i = i+1) begin
            if(issue_bus[i] matches tagged Valid .inst)
                rs_vec[i].in.instruction.put(inst);
        end
    endrule

    Wire#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) evo_wire <- mkWire();

    mkConnection(issue.decoded_inst, decode.decoded_inst);

    rule flush_prints;
        $fflush();
    endrule

    rule commit_to_fetch;
        let new_pc = commit.redirect_pc();
        regfile_evo.flush();
        ifu.redirect(new_pc);
        decode.flush();
    endrule

    rule connect_rob_issue;
        issue.rob_free(rob.free());
        issue.rob_current_idx(rob.current_idx());
    endrule

    rule connect_rob_issue2;
        let req = issue.get_reservation();
        rob.reserve(tpl_1(req), tpl_2(req));
    endrule

    mkConnection(issue.read_registers, regfile_evo.read_registers);
    mkConnection(issue.reserve_registers, regfile_evo.reserve_registers);

    interface imem_axi = ifu.imem_axi;
    interface dmem_axi_w = mem_arbiter.axi_w;
    interface dmem_axi_r = mem_arbiter.axi_r;

endmodule

endpackage
