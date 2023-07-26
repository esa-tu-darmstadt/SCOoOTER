package ExecCore;

/*
  This package connects all exec core components
*/

import Types::*;
import Inst_Types::*;
import Interfaces::*;
import GetPut::*;
import Connectable :: *;
import Vector::*;
import GetPutCustom::*;
import ClientServer::*;
import Issue::*;
import Arith::*;
import Mem::*;
import MulDiv::*;
import Branch::*;
import CSR::*;
import RegFileEvo::*;
import BuildVector::*;
import ReservationStation::*;
import ShiftBuffer::*;

interface ExecCoreIFC;
    // instruction input
    interface PutSC#(DecodeResponse, UInt#(TLog#(TAdd#(ISSUEWIDTH, 1)))) decoded_inst;

    // info from ROB
    (* always_ready, always_enabled *)
    method Action rob_free(UInt#(TLog#(TAdd#(ROBDEPTH,1))) free);
    (* always_ready, always_enabled *)
    method Action rob_current_idx(UInt#(TLog#(ROBDEPTH)) idx);
    // reserve space in ROB
    method Tuple2#(Vector#(ISSUEWIDTH, RobEntry), MIMO::LUInt#(ISSUEWIDTH)) get_reservation();

    // mispredict signal
    (* always_ready *)
    method Action flush();
    
    // read architectural registers
    interface Client#(Vector#(TMul#(2, ISSUEWIDTH), RADDR), Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) read_committed;

    // memory handling
    interface Client#(UInt#(XLEN), Maybe#(MaskedWord)) check_store_buffer;
    interface Client#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType))), Bit#(XLEN)) read;
    interface Client#(UInt#(TLog#(ROBDEPTH)), Bool) check_rob;
    method Action store_queue_empty(Bool b);

    // csr handling
    interface Client#(Bit#(12), Maybe#(Bit#(XLEN))) csr_read;
    (* always_ready, always_enabled *)
    method Action csr_busy(Bool b);

    // result bus output
    method Tuple3#(Vector#(NUM_FU, Maybe#(Result)), Maybe#(MemWr), Maybe#(CsrWrite)) res_bus;
endinterface

`ifdef SYNTH_SEPARATE_BLOCKS
    (* synthesize *)
`endif
module mkExecCore(ExecCoreIFC);

    // create issue stage 
    let issue <- mkIssue();

    // create speculative register file
    RegFileEvoIFC regfile_evo <- mkRegFileEvo();

    // instantiate all functional units
    Vector#(NUM_ALU, FunctionalUnitIFC) alus <- replicateM(mkArith());
    Vector#(NUM_MULDIV, FunctionalUnitIFC) mds <- replicateM(mkMulDiv());
    Vector#(NUM_BR, FunctionalUnitIFC) brs <- replicateM(mkBranch());
    let mem <- mkMem();
    let csr <- mkCSR();

    // generate the result bus
    let fu_vec = append(alus, append(append(mds, brs), vec(mem.fu, csr.fu)));
    function Maybe#(Result) get_result(FunctionalUnitIFC fu) = fu.get();
    let result_bus_vec = Vector::map(get_result, fu_vec);
    // generate the result bus with memory and CSR writes
    Maybe#(MemWr) mem_wr = isValid(mem.write()) ? tagged Valid mem.write.Valid : tagged Invalid;
    Maybe#(CsrWrite) csr_wr = isValid(csr.write()) ? tagged Valid csr.write.Valid : tagged Invalid;
    let full_result_bus_vec = tuple3(result_bus_vec, mem_wr, csr_wr);

    // generate the ReservationStations
    // ALU unit
    Vector#(NUM_ALU, ReservationStationWrIFC) rs_alus <- replicateM(mkReservationStationALU());
    Vector#(NUM_MULDIV, ReservationStationWrIFC) rs_mds <- replicateM(mkReservationStationMULDIV());
    //MEM unit
    ReservationStationWrIFC rs_mem <- mkReservationStationMEM();
    //branch unit
    Vector#(NUM_BR, ReservationStationWrIFC) rs_brs <- replicateM(mkReservationStationBR());
    //csr unit
    ReservationStationWrIFC rs_csr <- mkReservationStationCSR();
    Vector#(NUM_RS, ReservationStationWrIFC) rs_vec = 
        append(rs_alus, append(append(rs_mds, rs_brs), vec(rs_mem, rs_csr)));

    // connect RS and FUs
    for(Integer i = 0; i < valueOf(NUM_FU); i=i+1)
        rule rs_to_fu;
            let inst <- rs_vec[i].get();
            fu_vec[i].put(inst);
        endrule

    // map the FU results to a minimal bus for RS loopback
    function Maybe#(ResultLoopback) map_result_to_loopback_result(Maybe#(Result) a) = isValid(a) ? tagged Valid ResultLoopback {tag : a.Valid.tag, result : a.Valid.result.Result} : tagged Invalid;

    // connect results to issue stage and reservation stations   
    ShiftBufferIfc#(RESBUS_ADDED_DELAY, Vector#(NUM_RS, Maybe#(ResultLoopback))) delay_bus_rs <- mkShiftBuffer(replicate(tagged Invalid));
    rule input_result_bus_delay_loop;
        delay_bus_rs.r <= Vector::map(map_result_to_loopback_result, result_bus_vec);
    endrule 

    rule propagate_result_bus;
        for(Integer i = 0; i < valueOf(NUM_FU); i=i+1)
            rs_vec[i].result_bus(delay_bus_rs.r);
        regfile_evo.result_bus(delay_bus_rs.r);
    endrule

    // pass instructions from issue to rs
    function Bool get_rdy(ReservationStationWrIFC rs) = rs.in.can_insert();
    function ExecUnitTag get_op_type(ReservationStationWrIFC rs) = rs.unit_type();
    rule connect_rs_issue; // rdy signals
        let rdy_inst_vec = Vector::map(get_rdy, rs_vec);
        issue.rs_ready(rdy_inst_vec);
    endrule
    rule connect_rs_issue2; // type information
        let type_vec = Vector::map(get_op_type, rs_vec);
        issue.rs_type(type_vec);
    endrule
    rule connect_rs_issue3; // real instruction passing
        let issue_bus = issue.get_issue();
        for(Integer i = 0; i < valueOf(NUM_RS); i = i+1) begin
            if(issue_bus[i] matches tagged Valid .inst)
                rs_vec[i].in.instruction.put(inst);
        end
    endrule

    mkConnection(issue.reserve_registers, regfile_evo.reserve_registers);

    // combine speculative register file info with arch regs
    interface Client read_committed;
        interface Get request;
            method ActionValue#(Vector#(TMul#(2, ISSUEWIDTH), RADDR)) get();
                actionvalue
                    let req <- issue.read_registers.request.get();
                    regfile_evo.read_registers.request.put(req);
                    return req;
                endactionvalue
            endmethod
        endinterface
        interface Put response;
            method Action put(Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN)) resp);
                Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) evo <- regfile_evo.read_registers.response.get();
                for(Integer i = 0; i < valueof(ISSUEWIDTH)*2; i=i+1) begin
                    if (evo[i] matches tagged None) evo[i] = tagged Value resp[i]; // if evo reg is empty, use arch reg
                end
                 issue.read_registers.response.put(evo);
            endmethod
        endinterface
    endinterface

    // expose interfaces from internal units to outside world
    interface decoded_inst = issue.decoded_inst();
    method Action rob_free(UInt#(TLog#(TAdd#(ROBDEPTH,1))) free) = issue.rob_free(free);
    method Action rob_current_idx(UInt#(TLog#(ROBDEPTH)) idx);
        issue.rob_current_idx(idx);
        mem.current_rob_id(idx);
    endmethod
    interface Client check_rob = mem.check_rob;
    method Tuple2#(Vector#(ISSUEWIDTH, RobEntry), MIMO::LUInt#(ISSUEWIDTH)) get_reservation() = issue.get_reservation();
    method Action flush();
        mem.flush();
        regfile_evo.flush();
    endmethod
    method Action csr_busy(Bool b) = csr.block(b);
    interface Client check_store_buffer = mem.check_store_buffer();
    interface Client read = mem.request();
    method Tuple3#(Vector#(NUM_FU, Maybe#(Result)), Maybe#(MemWr), Maybe#(CsrWrite)) res_bus = full_result_bus_vec;
    interface Client csr_read = csr.csr_read;
    method Action store_queue_empty(Bool b) = mem.store_queue_empty(b);
endmodule

endpackage