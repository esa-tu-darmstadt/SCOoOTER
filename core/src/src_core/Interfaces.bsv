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

// Toplevel interface to external world
interface Top;
    (* prefix= "axi_master_fetch" *)
    interface AXI4_Master_Rd_Fab#(XLEN, TMul#(XLEN, IFUINST), 0, 0) imem_axi;
    (* prefix= "axi_master_data" *)
    interface AXI4_Master_Rd_Fab#(XLEN, XLEN, 1, 0) dmem_axi_r;
    (* prefix= "axi_master_data" *)
    interface AXI4_Master_Wr_Fab#(XLEN, XLEN, 1, 0) dmem_axi_w;

    `ifdef EVA_BR
        method UInt#(XLEN) correct_pred_br;
        method UInt#(XLEN) wrong_pred_br;
        method UInt#(XLEN) correct_pred_j;
        method UInt#(XLEN) wrong_pred_j;
    `endif
endinterface

interface MemoryArbiterIFC;
    // axi to data memory
    interface AXI4_Master_Rd_Fab#(XLEN, XLEN, 1, 0) axi_r;
    interface AXI4_Master_Wr_Fab#(XLEN, XLEN, 1, 0) axi_w;
    // normal reads/writes
    //interface Put#(MemWr) write;
    interface Server#(MemWr, void) write;
    interface Server#(Bit#(XLEN), Bit#(XLEN)) read;
    // TODO: add AMO
    interface Server#(Tuple3#(Bit#(XLEN), Bit#(XLEN), AmoType), Bit#(XLEN)) amo;
endinterface

// Instruction fetch unit iface
interface FetchIFC;
    // AXI to IMEM
    interface AXI4_Master_Rd_Fab#(XLEN, TMul#(XLEN, IFUINST), 0, 0) imem_axi;
    // mispredict signal
    method Action redirect(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)) in);
    // output
    interface GetS#(FetchResponse) instructions;

    interface Vector#(IFUINST, Client#(Bit#(XLEN), Prediction)) predict_direction;
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

    method Tuple2#(Vector#(ISSUEWIDTH, Tuple3#(RADDR, UInt#(TLog#(ROBDEPTH)), UInt#(XLEN))), MIMO::LUInt#(ISSUEWIDTH)) set_tags();
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

interface MemoryUnitIFC;
    interface FunctionalUnitIFC fu;
    interface Client#(UInt#(TLog#(ROBDEPTH)), Bool) check_rob;
    interface Client#(UInt#(XLEN), Maybe#(MaskedWord)) check_store_buffer;
    interface Client#(Bit#(XLEN), Bit#(XLEN)) read;
    interface Client#(Tuple3#(Bit#(XLEN), Bit#(XLEN), AmoType), Bit#(XLEN)) amo;
    method Action flush();
    method Action current_rob_id(UInt#(TLog#(ROBDEPTH)) idx);
endinterface

interface RobIFC;
    method UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) available;
    method UInt#(TLog#(TAdd#(ROBDEPTH,1))) free;
    (* always_enabled *)
    method UInt#(TLog#(ROBDEPTH)) current_idx;

    method Action reserve(Vector#(ISSUEWIDTH, RobEntry) data, UInt#(TLog#(TAdd#(1, ISSUEWIDTH))) num);
    method Vector#(ISSUEWIDTH, RobEntry) get();
    method Action complete_instructions(UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) count);

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);

    interface Server#(UInt#(TLog#(ROBDEPTH)), Bool) check_pending_memory;
    //method Bool check_pending_memory(UInt#(TLog#(ROBDEPTH)) idx);
endinterface

interface CommitIFC;
    method ActionValue#(UInt#(TLog#(TAdd#(ISSUEWIDTH,1)))) consume_instructions(Vector#(ISSUEWIDTH, RobEntry) instructions, UInt#(TLog#(TAdd#(ISSUEWIDTH,1))) count);
    method ActionValue#(Vector#(ISSUEWIDTH, Maybe#(RegWrite))) get_write_requests;
    method Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)) redirect_pc();
    interface Get#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) memory_writes;
    interface Get#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) train;

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
    method Vector#(31, Bit#(XLEN)) values();
endinterface

interface RegFileEvoIFC;

    interface Server#(Vector#(TMul#(2, ISSUEWIDTH), RADDR), Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) read_registers;
    interface Put#(RegReservations) reserve_registers;

    (* always_ready, always_enabled *)
    method Action committed_state(Vector#(31, Bit#(XLEN)) regs);
    //inform about misprediction
    method Action flush();
    (* always_ready, always_enabled *)
    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);
endinterface

interface StoreBufferIFC;
    interface Put#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) memory_writes;
    interface Server#(UInt#(XLEN), Maybe#(MaskedWord)) forward;
    interface Client#(MemWr, void) write;
endinterface

interface BTBIfc;
    interface Put#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) train;
    interface Server#(Bit#(XLEN), Vector#(IFUINST, Maybe#(Bit#(XLEN)))) predict;
endinterface

interface PredIfc;
    interface Put#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(TrainPrediction)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) train;
    interface Vector#(IFUINST, Server#(Bit#(XLEN), Prediction)) predict_direction;
endinterface

endpackage