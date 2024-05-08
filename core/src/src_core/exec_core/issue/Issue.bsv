package Issue;

/*
  ISSUE distributes incoming instructions amidst the RS
  and requests space in the ROB. ISSUE also reads and
  writes speculative register tags and provides those tags
  or already generated operands to the instructions.
*/

import Types::*;
import Inst_Types::*;
import Interfaces::*;
import Vector::*;
import Debug::*;
import GetPutCustom::*;
import GetPut::*;
import ClientServer::*;
import TestFunctions::*;
import BUtils::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkIssue(IssueIFC) provisos(
    // create types for ROB index and depth
    Log#(ROBDEPTH, size_logidx_t),
    Add#(ROBDEPTH, 1, robsize_pad_t),
    Log#(robsize_pad_t, robsize_log_t),

    // depending on the config, one type is bigger
    // to not loose precision, we need to know which in the impl
    Max#(issue_amount_t, robsize_log_t, issue_robamount_t),
    // tell the compiler that this largest type is larger than
    // the ones it is derived from
    Add#(__d, issue_amount_t, issue_robamount_t),
    Add#(__e, robsize_log_t, issue_robamount_t),
    Add#(__f, issuewidth_log_t, issue_robamount_t),
    // create instruction amount counters
    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),
    // create issue bus count types
    Add#(1, NUM_RS, rs_count_pad_t),
    Log#(rs_count_pad_t, rs_count_log_t),
    Log#(NUM_RS, rs_log_t),
    // create a type that holds the maximum issueable amount
    Max#(issuewidth_log_t, rs_count_log_t, issue_amount_t),
    Add#(__a, 1, issue_amount_t),

    Add#(__b, rs_count_log_t, issue_amount_t),
    Add#(__c, issuewidth_log_t, issue_amount_t)
);

`ifdef LOG_PIPELINE
    Reg#(UInt#(XLEN)) clk_ctr <- mkReg(0);
    rule count_clk; clk_ctr <= clk_ctr + 1; endrule
    Reg#(File) out_log <- mkRegU();
    Reg#(File) out_log_ko <- mkRegU();
    rule open if (clk_ctr == 0);
        File out_log_l <- $fopen("scoooter.log", "a");
        out_log <= out_log_l;
        File out_log_kol <- $fopen("konata.log", "a");
        out_log_ko <= out_log_kol;
    endrule
`endif

//wires for transport of incoming instructions
Wire#(Vector#(ISSUEWIDTH, Instruction)) inst_in <- mkWire();
Wire#(Bit#(ISSUEWIDTH)) inst_in_valid <- mkWire();

//wires to transport data from ROB
Wire#(UInt#(TLog#(TAdd#(ROBDEPTH,1)))) rob_free_w <- mkBypassWire();
Reg#(UInt#(TLog#(ROBDEPTH))) rob_idx_w <- mkReg(0);

//wires to transport signals from RS
Wire#(Vector#(NUM_RS, Bool)) rdy_inst_vec <- mkWire();
Wire#(Vector#(NUM_RS, ExecUnitTag)) op_type_vec <- mkWire();

//gather ready signals
let rs_free_type_vec = Vector::zip(op_type_vec, rdy_inst_vec);

//get next indices
Bit#(ROBDEPTH) dummy = 0;
function UInt#(rob_addr_t) generate_tag(UInt#(rob_addr_t) base, Integer i) = rollover_add(dummy, base, fromInteger(i));
Vector#(ISSUEWIDTH, UInt#(size_logidx_t)) rob_entry_idx_v = Vector::genWith(generate_tag(rob_idx_w));

//wires for transporting parts
Wire#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) gathered_operands <- mkWire();
Vector#(TMul#(2, ISSUEWIDTH), RWire#(UInt#(size_logidx_t))) cross_dependant_operands <- replicateM(mkRWire());
Wire#(Bit#(ISSUEWIDTH)) can_issue_mask <- mkWire();
Wire#(Vector#(ISSUEWIDTH, UInt#(rs_log_t))) needed_rs_idx_w <- mkWire();
Wire#(Vector#(TMul#(2, ISSUEWIDTH), RegRead)) req_addrs <- mkWire();

// helper function to extract destination RADDR from an instruction
function RADDR inst_to_raddr(Instruction inst) = (inst.has_rd ? truncate(inst.remaining_inst) : 0);
function RADDR inst_to_rs1(Instruction inst) = (inst.remaining_inst[12:8]);
function RADDR inst_to_rs2(Instruction inst) = (inst.remaining_inst[17:13]);

// REAL IMPLEMENTATION
// we use a lot of wires here to separate the distinct steps of issuing

// provide a read request to the register file
rule gather_operands;
    let instructions = inst_in;

    Vector#(TMul#(2, ISSUEWIDTH), RegRead) request_addrs;

    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
        request_addrs[2*i].addr = inst_to_rs1(inst_in[i]);
        request_addrs[2*i+1].addr = inst_to_rs2(inst_in[i]);
        request_addrs[2*i].thread_id = inst_in[i].thread_id;
        request_addrs[2*i+1].thread_id = inst_in[i].thread_id;
    end

    req_addrs <= request_addrs;
endrule

// test if an earlier instruction produces inputs to a later instruction
// in the incoming bundle
rule resolve_cross_dependencies;
    let instructions = inst_in;

    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
        
        //find out if a previous instruction modifies an operand
        Bool found_rs1 = False;
        Bool found_rs2 = False;
        
        // look at all earlier instructions
        for(Integer j = i; j > 0; j = j-1) begin

            // extract rd and epoch of inst to compare
            let rd_addr = inst_to_raddr(inst_in[j-1]);
            let epoch = inst_in[j-1].epoch;
            let thread_id = inst_in[j-1].thread_id;
            //check rs1
            if( rd_addr != 0 &&
                inst_in[i].has_rs1 &&
                rd_addr == inst_to_rs1(inst_in[i]) && !found_rs1 &&
                inst_in[i].epoch == epoch && 
                inst_in[i].thread_id == thread_id)
                begin
                    cross_dependant_operands[2*i].wset(rob_entry_idx_v[j-1]);
                    found_rs1 = True;
                end
            //check rs2
            if( rd_addr != 0 &&
                inst_in[i].has_rs2 &&
                rd_addr == inst_to_rs2(inst_in[i]) &&& !found_rs2 &&&
                inst_in[i].epoch == epoch &&
                inst_in[i].thread_id == thread_id)
                begin
                    cross_dependant_operands[2*i+1].wset(rob_entry_idx_v[j-1]);
                    found_rs2 = True;
                end
        end

    end
endrule

// helper function to test if an RS of certain type is ready
function Bool is_rdy_rs(ExecUnitTag eut, Tuple2#(ExecUnitTag, Bool) entry) = (eut == tpl_1(entry) && tpl_2(entry));

// find out how many instructions can be issued
// based on free RS, place in ROB, provided from window buffer
rule count_possible_issue;

    let instructions = inst_in;

    //for each instruction: can it be issued?
    Vector#(ISSUEWIDTH, Bool) can_issue = replicate(False);

    //for each instruction: which RS
    Vector#(ISSUEWIDTH, UInt#(rs_log_t)) needed_rs_idx = ?;


    Vector#(NUM_RS, Tuple2#(ExecUnitTag, Bool)) rs_free_type_vec_loc = rs_free_type_vec;
    //look at each instruction
    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin

        let idx = findElem(tuple2(instructions[i].eut, True), rs_free_type_vec_loc);
        if (idx matches tagged Valid .id &&& (i == 0 || can_issue[i-1])) begin
            can_issue[i] = True;
            needed_rs_idx[i] = id;
            rs_free_type_vec_loc[id] = unpack(0);
        end
    end

    //how much space is in ROB?
    function Bool is_in_bound(UInt#(TLog#(TAdd#(ROBDEPTH,1))) free, Integer idx) = fromInteger(idx) < free;
    Bit#(ISSUEWIDTH) can_enq_rob = pack(Vector::genWith(is_in_bound(rob_free_w)));

    // modify can_issue
    can_issue = unpack(pack(can_issue) & can_enq_rob & inst_in_valid);
    let max_issue = Vector::countElem(True, can_issue);

    // broadcast gathered insights
    can_issue_mask <= pack(can_issue);
    needed_rs_idx_w <= needed_rs_idx;
endrule

// create rob entry from instruction
function RobEntry map_to_rob_entry(Inst_Types::Instruction inst, UInt#(size_logidx_t) idx);
    return RobEntry {
        pc : inst.pc,
        destination : inst_to_raddr(inst),
        pred_pc : inst.predicted_pc,
        epoch : inst.epoch,
        next_pc : ?,
        branch : (inst.eut == BR),
        br : (inst.opc == BRANCH),
        history : inst.history,
        ras: inst.ras,
        ret: (inst.funct == RET),
        thread_id: inst.thread_id

        //RVFI
        `ifdef RVFI
            , iword: inst.iword,
              opc: inst.opc
        `endif
        `ifdef LOG_PIPELINE
            , log_id: inst.log_id
        `endif
        `ifdef DEXIE
            , dexie_type: (case (inst.opc)
                JAL, BRANCH, JALR: tagged Control;
                AMO, LOAD, STORE: tagged Memory;
                default: tagged Register;
                endcase)
            , dexie_iword: {inst.remaining_inst, pack(inst.opc)}
        `endif
    };
endfunction

// create issue entry from instruction
function InstructionIssue map_to_issued(Inst_Types::Instruction inst);
    return InstructionIssue {
        pc : inst.pc,
        opc : inst.opc,

        funct : inst.funct,

        // dummy values
        rs1 : ?,
        rs2 : ?,
        tag : ?,

        remaining_inst: inst.remaining_inst,

        exception : (inst.exception ? tagged Valid INVALID_INST : tagged Invalid),

        //RVFI
        `ifdef RVFI
            iword: inst.iword,
        `endif
        `ifdef LOG_PIPELINE
            log_id: inst.log_id,
        `endif

        epoch : inst.epoch,
        thread_id : inst.thread_id
    };
endfunction

Wire#(Vector#(ISSUEWIDTH, RobEntry)) rob_entry_wire <- mkWire();

// reserve space in the ROB
rule reserve_rob;
    let rob_entries = Vector::map(uncurry(map_to_rob_entry), Vector::zip(inst_in, rob_entry_idx_v));
    rob_entry_wire <= rob_entries;
endrule

Wire#(RegReservations) tag_res <- mkWire();

// set tags in the speculative register file
function RegReservation inst_to_register_reservation(Instruction ins, UInt#(size_logidx_t) idx) 
    = RegReservation { addr : inst_to_raddr(ins), tag: idx, epoch: ins.epoch, thread_id: ins.thread_id };
rule set_regfile_tags;
    Vector#(ISSUEWIDTH, RegReservation) reservations = Vector::map(uncurry(inst_to_register_reservation), Vector::zip(inst_in, rob_entry_idx_v));
    tag_res <= RegReservations {reservations: reservations, mask: can_issue_mask};
endrule

Wire#(Vector#(NUM_RS, Maybe#(InstructionIssue))) instructions_rs_v <- mkWire();

Reg#(Vector#(ISSUEWIDTH, InstructionIssue)) instructions_for_rs <- valueOf(SPLIT_ISSUE_STAGE) == 1 ? mkRegU() : mkBypassWire();
Reg#(Bit#(ISSUEWIDTH)) mask_for_rs <- valueOf(SPLIT_ISSUE_STAGE) == 1 ? mkReg(0) : mkBypassWire();
Wire#(Vector#(ISSUEWIDTH, UInt#(rs_log_t))) rs_ids_v <- valueOf(SPLIT_ISSUE_STAGE) == 1 ? mkRegU() : mkBypassWire();
// finally, assemble the instructions and issue them via the issue bus
rule assemble_instructions;
    Vector#(ISSUEWIDTH, InstructionIssue) instructions = Vector::map(map_to_issued, inst_in);

    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i = i+1) begin

        //first, set up all operands
        if(inst_in[i].has_rs1) begin
            if(cross_dependant_operands[i*2].wget() matches tagged Valid .tag) begin
                instructions[i].rs1 = tagged Tag tag;
            end else begin
                instructions[i].rs1 = case (gathered_operands[i*2]) matches
                    tagged Tag .t: tagged Tag t;
                    tagged Value .v: tagged Operand v;
                endcase;
            end
        end

        if(inst_in[i].has_rs2) begin
            if(cross_dependant_operands[i*2+1].wget() matches tagged Valid .tag) begin
                instructions[i].rs2 = tagged Tag tag;
            end else begin
                instructions[i].rs2 = case (gathered_operands[i*2+1]) matches
                    tagged Tag .t: tagged Tag t;
                    tagged Value .v: tagged Operand v;
                endcase;
            end
        end

        //then, set tag
        instructions[i].tag = rob_entry_idx_v[i];
    end

    //TODO: assembly of the issue bus is not yet ideal and is unregistered
    instructions_for_rs <= instructions;
    mask_for_rs <= can_issue_mask;
    rs_ids_v <= needed_rs_idx_w;
endrule

rule assemble_issue_bus;
    let instructions = instructions_for_rs;
    //then assemble issue bus
    Vector#(NUM_RS, Maybe#(InstructionIssue)) instructions_rs = replicate(tagged Invalid);

    for(Integer i = 0; i < valueOf(NUM_FU); i=i+1) begin
        let slot = Vector::findElem(fromInteger(i), rs_ids_v);
        if (slot matches tagged Valid .id &&& mask_for_rs[id] == 1) begin
            instructions_rs[i] = tagged Valid instructions[id];
            `ifdef LOG_PIPELINE
                $fdisplay(out_log, "%d ISSUE %x %d %d", clk_ctr, instructions[id].pc, instructions[id].tag, instructions[id].epoch);
                $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, instructions[id].log_id, 0, "I");
            `endif
            dbg_print(Issue, $format("Issuing ", fshow(instructions[id])));
        end
    end


    instructions_rs_v <= instructions_rs;
endrule

rule advance_issue_idx if (valueOf(ROBDEPTH) != 1);
    Bit#(ROBDEPTH) dummy = 0;
    let num_issued = Vector::countElem(True, unpack(can_issue_mask));
    if (ispwr2(dummy))
        rob_idx_w <= rob_idx_w + cExtend(num_issued);
    else begin
        UInt#(TAdd#(1, TLog#(ROBDEPTH))) rob_idx_w_ext = extend(rob_idx_w) + extend(num_issued);
        rob_idx_w <= (rob_idx_w_ext >= fromInteger(valueOf(ROBDEPTH)) ? truncate(rob_idx_w_ext - fromInteger(valueOf(ROBDEPTH))) : truncate(rob_idx_w_ext));
    end
endrule

// return issue bus
method Vector#(NUM_RS, Maybe#(InstructionIssue)) get_issue() = instructions_rs_v;
// inputs from ROB
method Action rob_free(UInt#(TLog#(TAdd#(ROBDEPTH,1))) free) = rob_free_w._write(free);
// reserve space in ROB
method Tuple2#(Vector#(ISSUEWIDTH, RobEntry), Bit#(ISSUEWIDTH)) get_reservation() 
    = tuple2(rob_entry_wire, can_issue_mask);
// input from the RS
method Action rs_ready(Vector#(NUM_RS, Bool) rdy) = rdy_inst_vec._write(rdy);
method Action rs_type(Vector#(NUM_RS, ExecUnitTag) in) = op_type_vec._write(in);
// get decoded instructions as input
interface PutSC decoded_inst;
    method Action put(DecodeResponse dec);
        inst_in <= dec.instructions;
        inst_in_valid <= dec.instruction_valid;
    endmethod
    method Bit#(ISSUEWIDTH) deq() = can_issue_mask;
endinterface
// read registers
interface Client read_registers;
    interface Get request;
        method ActionValue#(Vector#(TMul#(2, ISSUEWIDTH), RegRead)) get();
            actionvalue
                return req_addrs;
            endactionvalue
        endmethod
    endinterface
    interface Put response;
        method Action put(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) resp) = gathered_operands._write(resp);
    endinterface
endinterface
// provide tag requests to regfile_evo
interface Get reserve_registers;
    method ActionValue#(RegReservations) get();
        actionvalue
            return tag_res;
        endactionvalue
    endmethod
endinterface

endmodule


endpackage