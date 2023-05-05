package Interfaces;

import BlueAXI :: *;
import Types :: *;
import Inst_Types :: *;
import MIMO :: *;
import Vector :: *;
import List :: *;
import GetPut::*;
import GetPutCustom::*;
import ClientServer::*;

interface DaveIFC;

    (* prefix= "axi_master_fetch" *)
    interface AXI4_Master_Rd_Fab#(XLEN, TMul#(XLEN, IFUINST), TLog#(NUM_CPU), 0) imem_axi;
    (* prefix= "axi_master_data" *)
    interface AXI4_Master_Rd_Fab#(XLEN, XLEN, TAdd#(1, TLog#(NUM_CPU)), 0) dmem_axi_r;
    (* prefix= "axi_master_data" *)
    interface AXI4_Master_Wr_Fab#(XLEN, XLEN, TAdd#(1, TLog#(NUM_CPU)), 0) dmem_axi_w;

    (* always_ready, always_enabled *)
    method Action sw_int(Bool b);
    (* always_ready, always_enabled *)
    method Action timer_int(Bool b);
    (* always_ready, always_enabled *)
    method Action ext_int(Bool b);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif

endinterface

// Toplevel interface to external world
interface Top;
    interface Client#(MemWr, void) write_d;
    interface Client#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType))), Bit#(XLEN)) read_d;
    interface Client#(Bit#(XLEN), Bit#(TMul#(XLEN, IFUINST))) read_i;

    (* always_ready, always_enabled *)
    method Action sw_int(Bool b);
    (* always_ready, always_enabled *)
    method Action timer_int(Bool b);
    (* always_ready, always_enabled *)
    method Action ext_int(Bool b);
    (* always_ready, always_enabled *)
    method Action hart_id(Bit#(TLog#(NUM_CPU)) in);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif
endinterface

interface MemoryArbiterIFC;
    // axi to data memory
    interface AXI4_Master_Rd_Fab#(XLEN, XLEN, TAdd#(1, TLog#(NUM_CPU)), 0) axi_r;
    interface AXI4_Master_Wr_Fab#(XLEN, XLEN, TAdd#(1, TLog#(NUM_CPU)), 0) axi_w;
    // normal reads/writes
    interface Vector#(NUM_CPU, Server#(MemWr, void)) writes;
    interface Vector#(NUM_CPU, Server#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType))), Bit#(XLEN))) reads;
endinterface

interface InstArbiterIFC;
    // axi to data memory
    interface AXI4_Master_Rd_Fab#(XLEN, TMul#(XLEN, IFUINST), TLog#(NUM_CPU), 0) axi_r;
    interface Vector#(NUM_CPU, Server#(Bit#(XLEN), Bit#(TMul#(XLEN, IFUINST)))) reads;
endinterface

// Instruction fetch unit iface
interface FetchIFC;
    // to IMEM
    interface Client#(Bit#(XLEN), Bit#(TMul#(XLEN, IFUINST))) read;
    // mispredict signal
    method Action redirect(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)) in);
    // output
    interface GetS#(FetchResponse) instructions;

    interface Vector#(IFUINST, Client#(Tuple2#(Bit#(XLEN), Bool), Prediction)) predict_direction;
    interface Client#(Bit#(XLEN), Vector#(IFUINST, Maybe#(Bit#(XLEN)))) predict_target;
endinterface

interface DecodeIFC;
    // insert instructions here
    method Put#(FetchResponse) instructions;
    //output
    interface GetSC#(DecodeResponse, UInt#(TLog#(TAdd#(ISSUEWIDTH, 1)))) decoded_inst;
    //flush
    method Action flush();
endinterface

interface IssueIFC;
    //instruction input
    interface PutSC#(DecodeResponse, UInt#(TLog#(TAdd#(ISSUEWIDTH, 1)))) decoded_inst;

    //connection to regfile_evo
    interface Client#(Vector#(TMul#(2, ISSUEWIDTH), RADDR), Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) read_registers;
    interface Get#(RegReservations) reserve_registers;

    (* always_ready, always_enabled *)
    method Action rob_free(UInt#(TLog#(TAdd#(ROBDEPTH,1))) free);
    (* always_ready, always_enabled *)
    method Action rob_current_idx(UInt#(TLog#(ROBDEPTH)) idx);
    method Tuple2#(Vector#(ISSUEWIDTH, RobEntry), MIMO::LUInt#(ISSUEWIDTH)) get_reservation();

    method Action rs_ready(Vector#(NUM_RS, Bool) rdy);
    method Action rs_type(Vector#(NUM_RS, ExecUnitTag) in);

    method Vector#(NUM_RS, Maybe#(Instruction)) get_issue();


    interface Client#(Vector#(TMul#(2, ISSUEWIDTH), RADDR), Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) read_committed;
endinterface

interface ReservationStationPutIFC;
    interface Put#(Instruction) instruction;
    method Bool can_insert;
endinterface

interface ReservationStationIFC#(numeric type entries);
    method ActionValue#(Instruction) get;
    interface ReservationStationPutIFC in;
    (* always_ready, always_enabled *)
    method ExecUnitTag unit_type;
    (* always_ready, always_enabled *)
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);
endinterface

interface FunctionalUnitIFC;
    method Action put(Instruction inst);
    (* always_enabled *)
    method Maybe#(Result) get();
endinterface

interface CsrIFC;
    interface FunctionalUnitIFC fu;
    interface Client#(Bit#(12), Maybe#(Bit#(XLEN))) csr_read;
    method Action block(Bool b);
endinterface

interface MemoryUnitIFC;
    interface FunctionalUnitIFC fu;
    interface Client#(UInt#(TLog#(ROBDEPTH)), Bool) check_rob;
    interface Client#(UInt#(XLEN), Maybe#(MaskedWord)) check_store_buffer;
    interface Client#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType))), Bit#(XLEN)) request;
    method Action flush();
    method Action current_rob_id(UInt#(TLog#(ROBDEPTH)) idx);
    method Action store_queue_empty(Bool b);
endinterface

interface RobIFC;
    method UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) available;
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) free;
    (* always_enabled, always_ready *)
    method UInt#(TLog#(ROBDEPTH)) current_idx;

    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, UInt#(TLog#(TAdd#(1, ISSUEWIDTH))) num);
    method Vector#(ISSUEWIDTH, RobEntry) get();
    method Action complete_instructions(UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) count);

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);

    interface Server#(UInt#(TLog#(ROBDEPTH)), Bool) check_pending_memory;
    method Bool csr_busy();
endinterface

interface CommitIFC;
    method ActionValue#(UInt#(TLog#(TAdd#(ISSUEWIDTH,1)))) consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) count);
    method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    method Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)) redirect_pc();
    interface GetS#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) memory_writes;
    interface Get#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(CsrWrite)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) csr_writes;
    interface Get#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) train;

    method Action trap_vectors(Bit#(XLEN) tv, Bit#(XLEN) ret);
    method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(XLEN))) write_int_data();
    method Action ext_interrupt_mask(Bit#(3) in);

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif
endinterface

interface RegFileIFC;
    //write of architectural registers from commit stage
    method Action write(Vector#(ISSUEWIDTH, Maybe#(RegWrite)) requests);
    //output of current arch registers, used in mispredict
    interface Server#(Vector#(TMul#(2, ISSUEWIDTH), RADDR), Vector#(TMul#(2, ISSUEWIDTH), Bit#(XLEN))) read_registers;
endinterface

interface RegFileEvoIFC;
    interface Server#(Vector#(TMul#(2, ISSUEWIDTH), RADDR), Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) read_registers;
    interface Put#(RegReservations) reserve_registers;

    //inform about misprediction
    method Action flush();
    (* always_ready, always_enabled *)
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);
endinterface

interface StoreBufferIFC;
    interface Put#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) memory_writes;
    method Bool deq_memory_writes();
    interface Server#(UInt#(XLEN), Maybe#(MaskedWord)) forward;
    interface Client#(MemWr, void) write;
    method Bool empty();
endinterface

interface BTBIfc;
    interface Put#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) train;
    interface Server#(Bit#(XLEN), Vector#(IFUINST, Maybe#(Bit#(XLEN)))) predict;
endinterface

interface PredIfc;
    interface Put#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) train;
    interface Vector#(IFUINST, Server#(Tuple2#(Bit#(XLEN),Bool), Prediction)) predict_direction;
endinterface

interface CsrFileIFC;
    interface Put#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(CsrWrite)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) writes;
    interface Server#(Bit#(12), Maybe#(Bit#(XLEN))) read;
    method Tuple2#(Bit#(XLEN), Bit#(XLEN)) trap_vectors();
    method Action write_int_data(Bit#(XLEN) cause, Bit#(XLEN) pc);
    method Bit#(3) ext_interrupt_mask();
    (* always_ready, always_enabled *)
    method Action hart_id(Bit#(TLog#(NUM_CPU)) in);
endinterface

endpackage