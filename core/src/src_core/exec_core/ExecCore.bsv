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
import StoreBuffer::*;


interface ExecCoreIFC;
    // instruction input
    interface PutSC#(DecodeResponse, Bit#(ISSUEWIDTH)) decoded_inst;

    // info from ROB
    (* always_ready, always_enabled *)
    method Action rob_free(UInt#(TLog#(TAdd#(ROBDEPTH,1))) free);
    (* always_ready, always_enabled *)
    method Action rob_current_tail_idx(UInt#(TLog#(ROBDEPTH)) idx);
    // reserve space in ROB
    method Tuple2#(Vector#(ISSUEWIDTH, RobEntry), Bit#(ISSUEWIDTH)) get_reservation();

    // mispredict signal
    (* always_ready *)
    method Action flush(Vector#(NUM_THREADS, Bool) in);
    
    // read architectural registers
    interface Client#(Vector#(TMul#(2, ISSUEWIDTH), RegRead), Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) read_committed;

    // memory handling
    interface Client#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType))), Bit#(XLEN)) read;

    interface Client#(MemWr, void) write;

    // csr handling
    interface Client#(CsrRead, Maybe#(Bit#(XLEN))) csr_read;
    interface Get#(CsrWrite) csr_write;    

    // result bus output
    method Vector#(NUM_FU, Maybe#(Result)) res_bus;

    // signals for DExIE
    `ifdef DEXIE
        method Maybe#(DexieMem) dexie_memw;
        (* always_ready, always_enabled *)
        method Action dexie_stall(Bool stall);
    `endif
endinterface

`ifdef SYNTH_SEPARATE_BLOCKS
    (* synthesize *)
`endif
module mkExecCore(ExecCoreIFC);

    // create issue stage 
    let issue <- mkIssue();

    // create speculative register file
    RegFileEvoIFC regfile_evo <- (valueOf(ROB_BANK_DEPTH) == 1 && valueOf(ISSUEWIDTH) == 1 ? mkRegFileEvo_dummy() : mkRegFileEvo());

    // instantiate all functional units
    Vector#(NUM_ALU, FunctionalUnitIFC) alus <- replicateM(mkArith());
    Vector#(NUM_MULDIV, FunctionalUnitIFC) mds <- replicateM(mkMulDiv());
    Vector#(NUM_BR, FunctionalUnitIFC) brs <- replicateM(mkBranch());
    let mem <- mkMem();
    let csr <- mkCSR();

    // initialize and connect store buffer
    let store_buf <- mkStoreBuffer();
    mkConnection(mem.check_store_buffer, store_buf.forward);
    mkConnection(mem.write, store_buf.memory_write);
    
    // state signals for store_buffer <-> mem unit
    rule fwd_empty_sb;
        mem.store_queue_empty(store_buf.empty());
        mem.store_queue_full(store_buf.full());
    endrule

    // generate the result bus
    // build vector with all FUs
    let fu_vec = append(alus, append(append(mds, brs), vec(mem.fu, csr.fu)));
    // map FU vector to results
    function Maybe#(Result) get_result(FunctionalUnitIFC fu) = fu.get();
    let result_bus_vec = Vector::map(get_result, fu_vec);

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
    // vector of all RSs
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
        let loopback = Vector::map(map_result_to_loopback_result, result_bus_vec);
        // provide result immediately to regfile evo
        regfile_evo.result_bus(loopback);
        // delay bus if requested for reamining components
        delay_bus_rs.r <= loopback;
    endrule 

    // fwd results to reservation stations
    rule propagate_result_bus;
        for(Integer i = 0; i < valueOf(NUM_FU); i=i+1)
            rs_vec[i].result_bus(delay_bus_rs.r);
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

    // connect issue to evo regfile
    mkConnection(issue.reserve_registers, regfile_evo.reserve_registers);

    // combine speculative register file info with arch regs
    interface Client read_committed;
        interface Get request;
            method ActionValue#(Vector#(TMul#(2, ISSUEWIDTH), RegRead)) get();
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
    method Action rob_current_tail_idx(UInt#(TLog#(ROBDEPTH)) idx);
        mem.current_rob_id(idx);
        csr.current_rob_id(idx);
    endmethod

    // provide register reservations to ROB / backend
    method Tuple2#(Vector#(ISSUEWIDTH, RobEntry), Bit#(ISSUEWIDTH)) get_reservation() = issue.get_reservation();
    
    // connect pipeline flush signals
    method Action flush(Vector#(NUM_THREADS, Bool) in);
        mem.flush(in);
        regfile_evo.flush(in);
        csr.flush(in);
    endmethod

    // connect memory read/write iface
    interface Client read = mem.request();
    interface write = store_buf.write;

    // connect CSR read/write
    interface Client csr_read = csr.csr_read;
    interface Get csr_write = csr.write;

    // provide result bus to output
    method Vector#(NUM_FU, Maybe#(Result)) res_bus = result_bus_vec;
    
    // DExIE signal output
    `ifdef DEXIE
        method Maybe#(DexieMem) dexie_memw = mem.dexie_memw;
        interface dexie_stall = mem.dexie_stall();
    `endif
endmodule

endpackage