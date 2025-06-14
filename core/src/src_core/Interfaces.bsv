package Interfaces;

/*

Interfaces for all units

*/

import BlueAXI :: *;
import Types :: *;
import Inst_Types :: *;
import MIMO :: *;
import Vector :: *;
import List :: *;
import GetPut::*;
import GetPutCustom::*;
import ClientServer::*;

interface MemMappedIFC#(numeric type addrwidth);
    interface Server#(Tuple2#(UInt#(addrwidth), Bit#(TAdd#(TLog#(NUM_CPU), 1))), Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) mem_r;
    interface Server#(Tuple4#(UInt#(addrwidth), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))), Bit#(TAdd#(TLog#(NUM_CPU), 1))) mem_w;
endinterface

interface DaveAXIWrapper;
    (* prefix="axi_master_fetch" *)
    interface AXI4_Lite_Master_Rd_Fab#(XLEN, TMul#(XLEN, IFUINST)) imem_r;
    (* prefix="axi_master_fetch" *)
    interface AXI4_Lite_Master_Wr_Fab#(XLEN, TMul#(XLEN, IFUINST)) imem_w;

    (* prefix="axi_master_data" *)
    interface AXI4_Lite_Master_Rd_Fab#(XLEN, XLEN) dmem_r;
    (* prefix="axi_master_data" *)
    interface AXI4_Lite_Master_Wr_Fab#(XLEN, XLEN) dmem_w;

    (* always_ready, always_enabled *)
    method Action sw_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) b);
    (* always_ready, always_enabled *)
    method Action timer_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) b);
    (* always_ready, always_enabled *)
    method Action ext_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) b);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif

    `ifdef DEXIE
        interface Vector#(NUM_CPU, DExIEIfc) dexie;
    `endif
endinterface : DaveAXIWrapper

interface DaveIFC;
    interface Client#(Tuple2#(UInt#(XLEN), Bit#(TLog#(NUM_CPU))), Tuple2#(Bit#(TMul#(XLEN, IFUINST)), Bit#(TLog#(NUM_CPU)))) imem_r;
    interface Client#(Tuple2#(UInt#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1))), Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) dmem_r;
    interface Client#(Tuple4#(UInt#(XLEN), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))), Bit#(TAdd#(TLog#(NUM_CPU), 1))) dmem_w;

    (* always_ready, always_enabled *)
    method Action sw_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in);
    (* always_ready, always_enabled *)
    method Action timer_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in);
    (* always_ready, always_enabled *)
    method Action ext_int(Vector#(NUM_CPU, Vector#(NUM_THREADS, Bool)) in);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif

    `ifdef DEXIE
        interface Vector#(NUM_CPU, DExIEIfc) dexie;
    `endif

endinterface

// Toplevel interface to external world
interface Top;
    interface Client#(MemWr, void) write_d;
    interface Client#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType))), Bit#(XLEN)) read_d;
    interface Client#(Bit#(XLEN), Bit#(TMul#(XLEN, IFUINST))) read_i;

    (* always_ready, always_enabled *)
    method Action sw_int(Vector#(NUM_THREADS, Bool) b);
    (* always_ready, always_enabled *)
    method Action timer_int(Vector#(NUM_THREADS, Bool) b);
    (* always_ready, always_enabled *)
    method Action ext_int(Vector#(NUM_THREADS, Bool) b);
    (* always_ready, always_enabled *)
    method Action hart_id(Bit#(TLog#(TMul#(NUM_CPU, NUM_THREADS))) in);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif

    `ifdef DEXIE
        interface DExIEIfc dexie;
    `endif
endinterface

interface MemoryArbiterIFC;
    // simple iface to data memory / periphery
    interface Client#(Tuple2#(UInt#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1))), Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) dmem_r;
    interface Client#(Tuple4#(UInt#(XLEN), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))), Bit#(TAdd#(TLog#(NUM_CPU), 1))) dmem_w;
    // normal reads/writes
    interface Vector#(NUM_CPU, Server#(MemWr, void)) writes;
    interface Vector#(NUM_CPU, Server#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType))), Bit#(XLEN))) reads;
endinterface

interface InstArbiterIFC;
    interface Client#(Tuple2#(UInt#(XLEN), Bit#(TLog#(NUM_CPU))), Tuple2#(Bit#(TMul#(XLEN, IFUINST)), Bit#(TLog#(NUM_CPU)))) imem_r;
    interface Vector#(NUM_CPU, Server#(Bit#(XLEN), Bit#(TMul#(XLEN, IFUINST)))) reads;
endinterface

// Instruction fetch unit iface
interface FetchIFC;
    // to IMEM
    interface Client#(Bit#(XLEN), Bit#(TMul#(XLEN, IFUINST))) read;
    // mispredict signal
    (* always_ready, always_enabled *)
    method Action redirect(Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) in);
    // output
    interface GetS#(FetchResponse) instructions;

    interface Vector#(IFUINST, Client#(Tuple2#(Bit#(PCLEN), Bool), Prediction)) predict_direction;
    interface Client#(Bit#(PCLEN), Vector#(IFUINST, Maybe#(Bit#(PCLEN)))) predict_target;

    (* always_ready, always_enabled *)
    method UInt#(TLog#(NUM_THREADS)) current_thread();
endinterface

interface DecodeIFC;
    // insert instructions here
    method Put#(FetchResponse) instructions;
    //output
    interface GetSC#(DecodeResponse, Bit#(ISSUEWIDTH)) decoded_inst;
    //flush
    method Action flush();
endinterface

interface IssueIFC;
    //instruction input
    interface PutSC#(DecodeResponse, Bit#(ISSUEWIDTH)) decoded_inst;

    //connection to regfile_evo
    interface Client#(Vector#(TMul#(2, ISSUEWIDTH), RegRead), Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) read_registers;
    interface Get#(RegReservations) reserve_registers;

    (* always_ready, always_enabled *)
    method Action rob_free(UInt#(TLog#(TAdd#(ROBDEPTH,1))) free);
    method Tuple2#(Vector#(ISSUEWIDTH, RobEntry), Bit#(ISSUEWIDTH)) get_reservation();

    method Action rs_ready(Vector#(NUM_RS, Bool) rdy);
    method Action rs_type(Vector#(NUM_RS, ExecUnitTag) in);

    method Vector#(NUM_RS, Maybe#(InstructionIssue)) get_issue();
endinterface

interface ReservationStationPutIFC;
    interface Put#(InstructionIssue) instruction;
    method Bool can_insert;
endinterface

interface ReservationStationIFC#(numeric type entries);
    method ActionValue#(InstructionIssue) get;
    interface ReservationStationPutIFC in;
    (* always_ready, always_enabled *)
    method ExecUnitTag unit_type;
    (* always_ready, always_enabled *)
    method Action result_bus(Vector#(NUM_FU, Maybe#(ResultLoopback)) bus_in);
endinterface

interface FunctionalUnitIFC;
    method Action put(InstructionIssue inst);
    (* always_enabled *)
    method Maybe#(Result) get();
endinterface

interface CsrIFC;
    interface FunctionalUnitIFC fu;
    interface Client#(CsrRead, Maybe#(Bit#(XLEN))) csr_read;
    interface Get#(CsrWrite) write;
    method Action current_rob_id(UInt#(TLog#(ROBDEPTH)) idx);
    method Action flush(Vector#(NUM_THREADS, Bool) in);
endinterface

interface MemoryUnitIFC;
    interface FunctionalUnitIFC fu;
    interface Client#(UInt#(XLEN), Maybe#(MaskedWord)) check_store_buffer;
    interface Client#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType))), Bit#(XLEN)) request;
    method Action flush(Vector#(NUM_THREADS, Bool) in);
    method Action current_rob_id(UInt#(TLog#(ROBDEPTH)) idx);
    method Action store_queue_empty(Bool b);
    method Action store_queue_full(Bool b);
    interface Get#(MemWr) write;

    `ifdef DEXIE
        method Maybe#(DexieMem) dexie_memw;
        (* always_ready, always_enabled *)
        method Action dexie_stall(Bool stall);
    `endif
endinterface

interface RobIFC;
    method UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) available;
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) free;
    (* always_enabled, always_ready *)
    method UInt#(TLog#(ROBDEPTH)) current_tail_idx;

    (* always_enabled, always_ready *)
    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, Bit#(ISSUEWIDTH) mask);
    method ActionValue#(Vector#(ISSUEWIDTH, RobEntry)) get();

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) res_bus);

    `ifdef DEXIE
        (* always_ready, always_enabled *)
        method Action dexie_stall(Bool stall);
    `endif
endinterface

interface CommitIFC;
    method Action consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) count);
    method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    method Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirect_pc();
    interface Get#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) train;

    method Action trap_vectors(Vector#(NUM_THREADS, Tuple2#(Bit#(XLEN), Bit#(XLEN))) vecs);
    method ActionValue#(Vector#(NUM_THREADS, Maybe#(TrapDescription))) write_int_data();
    method Action ext_interrupt_mask(Vector#(NUM_THREADS, Bit#(3)) in);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif

    `ifdef RVFI
        (* always_ready,always_enabled *)
        method Vector#(ISSUEWIDTH, RVFIBus) rvfi_out;
    `endif

    `ifdef DEXIE
        interface DExIETraceIfc dexie;
        (* always_ready, always_enabled *)
        method Action dexie_stall(Bool stall);
    `endif
endinterface

interface RegFileIFC;
    //write of architectural registers from commit stage
    method Action write(Vector#(ISSUEWIDTH, Maybe#(RegWrite)) requests);
    //output of current arch registers, used in mispredict
    interface Server#(Vector#(TMul#(2, ISSUEWIDTH), RegRead), Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) read_registers;
endinterface

interface RegFileEvoIFC;
    interface Server#(Vector#(TMul#(2, ISSUEWIDTH), RegRead), Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) read_registers;
    interface Put#(RegReservations) reserve_registers;

    //inform about misprediction
    method Action flush(Vector#(NUM_THREADS, Bool) flags);
    (* always_ready, always_enabled *)
    method Action result_bus(Vector#(NUM_FU, Maybe#(ResultLoopback)) bus_in);
endinterface

interface StoreBufferIFC;
    interface Put#(MemWr) memory_write;
    interface Server#(UInt#(XLEN), Maybe#(MaskedWord)) forward;
    interface Client#(MemWr, void) write;
    method Bool empty();
    method Bool full();
endinterface

interface BTBIfc;
    interface Put#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) train;
    interface Server#(Bit#(PCLEN), Vector#(IFUINST, Maybe#(Bit#(PCLEN)))) predict;
endinterface

interface PredIfc;
    interface Put#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction))) train;
    interface Vector#(IFUINST, Server#(Tuple2#(Bit#(PCLEN),Bool), Prediction)) predict_direction;
    (* always_ready, always_enabled *)
    method Action current_thread(UInt#(TLog#(NUM_THREADS)) thread_id);
endinterface

interface CsrFileIFC;
    interface Put#(CsrWrite) write;
    interface Server#(CsrRead, Maybe#(Bit#(XLEN))) read;
    method Vector#(NUM_THREADS, Tuple2#(Bit#(XLEN), Bit#(XLEN))) trap_vectors();
    method Action write_int_data(Vector#(NUM_THREADS, Maybe#(TrapDescription)) in);
    method Vector#(NUM_THREADS, Bit#(3)) ext_interrupt_mask();
    (* always_ready, always_enabled *)
    method Action hart_id(Bit#(TLog#(TMul#(NUM_CPU, NUM_THREADS))) in);
endinterface

interface DExIETraceIfc;

    (*always_ready, always_enabled*)
    method Vector#(ISSUEWIDTH, Maybe#(DexieCF)) cf;
    (*always_ready, always_enabled*)
    method Vector#(ISSUEWIDTH, Maybe#(DexieReg)) regw;
    (*always_ready, always_enabled*)
    method Maybe#(DexieMem) memw;
endinterface

interface DExIEIfc;

    (*always_ready, always_enabled*)
    method Vector#(ISSUEWIDTH, Maybe#(DexieCF)) cf;
    (*always_ready, always_enabled*)
    method Vector#(ISSUEWIDTH, Maybe#(DexieReg)) regw;
    (*always_ready, always_enabled*)
    method Maybe#(DexieMem) memw;

    (*always_ready, always_enabled*)
    method Action stall_signals(Bool control, Bool store);
endinterface

endpackage
