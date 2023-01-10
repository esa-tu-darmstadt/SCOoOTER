package Issue;

import Types::*;
import Inst_Types::*;
import Interfaces::*;
import Vector::*;
import Debug::*;
import GetPutCustom::*;
import GetPut::*;
import ClientServer::*;

(* synthesize *)
module mkIssue(IssueIFC) provisos(
    Log#(ROBDEPTH, size_logidx_t),
    Add#(ROBDEPTH, 1, robsize_pad_t),
    Log#(robsize_pad_t, robsize_log_t),
    Max#(issue_amount_t, robsize_log_t, issue_robamount_t),
    Add#(__d, issue_amount_t, issue_robamount_t),
    Add#(__e, robsize_log_t, issue_robamount_t),
    Add#(__f, issuewidth_log_t, issue_robamount_t),

    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),
    Add#(1, NUM_RS, rs_count_pad_t),
    Log#(rs_count_pad_t, rs_count_log_t),
    Max#(issuewidth_log_t, rs_count_log_t, issue_amount_t),
    Add#(__a, 1, issue_amount_t),

    Add#(__b, rs_count_log_t, issue_amount_t),
    Add#(__c, issuewidth_log_t, issue_amount_t)
);

//wires for transport of incoming instructions
Wire#(Vector#(ISSUEWIDTH, Instruction)) inst_in <- mkWire();
Wire#(MIMO::LUInt#(ISSUEWIDTH)) inst_in_cnt <- mkWire();

Wire#(UInt#(TLog#(TAdd#(ROBDEPTH,1)))) rob_free_w <- mkBypassWire();
Wire#(UInt#(TLog#(ROBDEPTH))) rob_idx_w <- mkBypassWire();

Wire#(Vector#(NUM_RS, Bool)) rdy_inst_vec <- mkWire();
Wire#(Vector#(NUM_RS, ExecUnitTag)) op_type_vec <- mkWire();

//gather ready signals
let rs_free_type_vec = Vector::zip(op_type_vec, rdy_inst_vec);

//get next indices
function UInt#(rob_addr_t) generate_tag(UInt#(rob_addr_t) base, Integer i) = base + fromInteger(i);
Vector#(ISSUEWIDTH, UInt#(size_logidx_t)) rob_entry_idx_v = Vector::genWith(generate_tag(rob_idx_w));

//wires for transporting parts
Wire#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) gathered_operands <- mkWire();
Vector#(TMul#(2, ISSUEWIDTH), RWire#(UInt#(size_logidx_t))) cross_dependant_operands <- replicateM(mkRWire());
Wire#(UInt#(issuewidth_log_t)) possible_issue_amount <- mkWire();
Wire#(Vector#(ISSUEWIDTH, UInt#(rs_count_log_t))) needed_rs_idx_w <- mkWire();
Wire#(Vector#(TMul#(2, ISSUEWIDTH), RADDR)) req_addrs <- mkWire();

function RADDR inst_to_raddr(Instruction inst) = (inst.rd matches tagged Raddr .r ? r : 0);

rule gather_operands;
    let instructions = inst_in;

    Vector#(TMul#(2, ISSUEWIDTH), RADDR) request_addrs;

    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
        request_addrs[2*i] = inst_in[i].rs1.Raddr;
        request_addrs[2*i+1] = inst_in[i].rs2.Raddr;
    end

    dbg_print(Issue, $format("Requesting operands: ", fshow(request_addrs)));

    req_addrs <= request_addrs;
endrule

rule resolve_cross_dependencies;
    let instructions = inst_in;

    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
        
        //find out if a previous instruction modifies an operand
        Bool found_rs1 = False;
        Bool found_rs2 = False;
        
        for(Integer j = i; j > 0; j = j-1) begin
            //check rs1
            if(inst_in[j-1].rd matches tagged Raddr .rd_addr &&&
                rd_addr != 0 &&&
                inst_in[i].rs1 matches tagged Raddr .rs1_addr &&&
                rd_addr == rs1_addr &&& !found_rs1 )
                begin
                    cross_dependant_operands[2*i].wset(rob_entry_idx_v[j-1]);
                    found_rs1 = True;
                end
            //check rs2
            if(inst_in[j-1].rd matches tagged Raddr .rd_addr &&&
                rd_addr != 0 &&&
                inst_in[i].rs2 matches tagged Raddr .rs2_addr &&&
                rd_addr == rs2_addr &&& !found_rs2 )
                begin
                    cross_dependant_operands[2*i+1].wset(rob_entry_idx_v[j-1]);
                    found_rs2 = True;
                end
        end

    end
endrule

function Bool is_rdy_rs(ExecUnitTag eut, Tuple2#(ExecUnitTag, Bool) entry) = (eut == tpl_1(entry) && tpl_2(entry));

//TODO: use less sequential algorithm
function UInt#(a) find_nth(UInt#(a) num, b cmp, Vector#(c, b) vec) provisos(
    Eq#(b)
);
    UInt#(a) found = 0;
    UInt#(a) out = ?;
    for(Integer i = 0; i < valueOf(c); i = i + 1) begin
        if(vec[i] == cmp) begin
            found = found + 1;
            if(found == num) out = fromInteger(i);
        end
    end
    return out;
endfunction

rule count_possible_issue;
    let instructions = inst_in;

    //for each instruction: can it be issued?
    Vector#(ISSUEWIDTH, Bool) can_issue = replicate(True);

    //for each instruction: which RS
    Vector#(ISSUEWIDTH, UInt#(rs_count_log_t)) needed_rs_idx = ?;

    //look at each instruction
    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin

        //count how many rs of our type are ready
        UInt#(issue_amount_t) rdy_cnt = extend(Vector::countIf(is_rdy_rs(instructions[i].eut), rs_free_type_vec));
        
        //count how many previous instructions (and this inst) are of the same type
        UInt#(issue_amount_t) need_issue_cnt = 1;
        for(Integer j = 0; j < valueOf(ISSUEWIDTH); j=j+1) begin
            if(instructions[i].eut == instructions[j].eut && j < i) begin
                need_issue_cnt = need_issue_cnt + 1;
            end
        end

        needed_rs_idx[i] = truncate(find_nth(need_issue_cnt, tuple2(instructions[i].eut, True), rs_free_type_vec));

        //if more inst to issue than available, this inst cannot issue
        can_issue[i] = (rdy_cnt >= need_issue_cnt);
    end

    //find first impossible issue
    let max_issue_rs_m = Vector::findElem(False, can_issue);
    UInt#(issue_amount_t) max_issue_rs = case (max_issue_rs_m) matches
        tagged Invalid:  fromInteger(valueOf(ISSUEWIDTH));
        tagged Valid .v: extend(v);
    endcase;

    //how much space is in ROB?
    UInt#(issue_robamount_t) rob_av_ext = extend(rob_free_w);
    UInt#(issue_robamount_t) rs_avail = extend(max_issue_rs);

    UInt#(issuewidth_log_t) max_issue = (extend(max_issue_rs) > rob_av_ext ? truncate(rob_av_ext) : truncate(rs_avail));

    possible_issue_amount <= max_issue > inst_in_cnt ? inst_in_cnt : max_issue;

    needed_rs_idx_w <= needed_rs_idx;

    //dbg_print(Issue, $format("possible issue (rs): ", max_issue_rs));
    //dbg_print(Issue, $format("possible issue (rob): ", rob_av_ext));
    //dbg_print(Issue, $format("possible issue (inst_in): ", inst_in_cnt));

endrule

function RobEntry map_to_rob_entry(Inst_Types::Instruction inst, UInt#(size_logidx_t) idx);
    return RobEntry {
        pc : inst.pc,
        destination : inst.rd.Raddr,
        result : (isValid(inst.exception) ?
            tagged Except fromMaybe(?, inst.exception) :
            tagged Tag idx),
        pred_pc : (inst.pc+4),
        epoch : inst.epoch,
        next_pc : ?
    };
endfunction

Wire#(Vector#(ISSUEWIDTH, RobEntry)) rob_entry_wire <- mkWire();

rule reserve_rob;
    let rob_entries = Vector::map(uncurry(map_to_rob_entry), Vector::zip(inst_in, rob_entry_idx_v));
    //rob.reserve(rob_entries, possible_issue_amount);
    rob_entry_wire <= rob_entries;
endrule

Wire#(RegReservations) tag_res <- mkWire();

function RegReservation inst_to_register_reservation(Instruction ins, UInt#(size_logidx_t) idx) 
    = RegReservation { addr : (ins.rd matches tagged Raddr .rd ? rd : 0), tag: idx, epoch: ins.epoch };
rule set_regfile_tags;
    Vector#(ISSUEWIDTH, RegReservation) reservations = Vector::map(uncurry(inst_to_register_reservation), Vector::zip(inst_in, rob_entry_idx_v));

    tag_res <= RegReservations {reservations: reservations, count: possible_issue_amount};
endrule

Wire#(Vector#(NUM_RS, Maybe#(Instruction))) instructions_rs_v <- mkWire();

rule assemble_instructions;
    Vector#(ISSUEWIDTH, Instruction) instructions = inst_in;

    dbg_print(Issue, $format("Got operands: ", fshow(gathered_operands)));

    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i = i+1) begin

        //first, set up all operands
        if(instructions[i].rs1 matches tagged Raddr .register) begin
            if(cross_dependant_operands[i*2].wget() matches tagged Valid .tag) begin
                instructions[i].rs1 = tagged Tag tag;
            end else begin
                instructions[i].rs1 = case (gathered_operands[i*2]) matches
                    tagged Tag .t: tagged Tag t;
                    tagged Value .v: tagged Operand v;
                endcase;
            end
        end

        if(instructions[i].rs2 matches tagged Raddr .register) begin
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

    //then assemble issue bus
    Vector#(NUM_RS, Maybe#(Instruction)) instructions_rs = replicate(tagged Invalid);

    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i = i+1) begin
        if(fromInteger(i) < possible_issue_amount) begin
            instructions_rs[needed_rs_idx_w[i]] = tagged Valid instructions[i];
        end
    end

    instructions_rs_v <= instructions_rs;

    dbg_print(Issue, $format("Issue_bus ", fshow(instructions_rs)));
endrule

function UInt#(32) inst_to_epoch(Instruction inst) = inst.epoch;

method Vector#(NUM_RS, Maybe#(Instruction)) get_issue();
    return instructions_rs_v;
endmethod

method Action rob_free(UInt#(TLog#(TAdd#(ROBDEPTH,1))) free);
    rob_free_w <= free;
endmethod
method Action rob_current_idx(UInt#(TLog#(ROBDEPTH)) idx);
    rob_idx_w <= idx;
endmethod

method Tuple2#(Vector#(ISSUEWIDTH, RobEntry), UInt#(issuewidth_log_t)) get_reservation();
    return tuple2(rob_entry_wire, possible_issue_amount);
endmethod

method Action rs_ready(Vector#(NUM_RS, Bool) rdy);
    rdy_inst_vec <= rdy;
endmethod

method Action rs_type(Vector#(NUM_RS, ExecUnitTag) in);
    op_type_vec <= in;
endmethod

method Tuple2#(Vector#(ISSUEWIDTH, Tuple3#(RADDR, UInt#(TLog#(ROBDEPTH)), UInt#(XLEN))), MIMO::LUInt#(ISSUEWIDTH)) set_tags();
    Vector#(ISSUEWIDTH, Instruction) instructions = inst_in;

    let raddrs = Vector::map(inst_to_raddr, instructions);
    let epochs = Vector::map(inst_to_epoch, instructions);
    let raddr_and_tag = Vector::zip3(raddrs, rob_entry_idx_v, epochs);

    return tuple2(raddr_and_tag, possible_issue_amount);
endmethod

interface PutSC decoded_inst;
    method Action put(DecodeResponse dec);
        inst_in <= dec.instructions;
        inst_in_cnt <= dec.count;
    endmethod
    method MIMO::LUInt#(ISSUEWIDTH) deq() = possible_issue_amount;
endinterface

interface Client read_registers;

    interface Get request;
        method ActionValue#(Vector#(TMul#(2, ISSUEWIDTH), RADDR)) get();
            actionvalue
                return req_addrs;
            endactionvalue
        endmethod
    endinterface

    interface Put response;
        method Action put(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) resp) = gathered_operands._write(resp);
    endinterface

endinterface

interface Get reserve_registers;
    method ActionValue#(RegReservations) get();
        actionvalue
            return tag_res;
        endactionvalue
    endmethod
endinterface

endmodule


endpackage