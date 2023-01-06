package Issue;

import Types::*;
import Inst_Types::*;
import Interfaces::*;
import Vector::*;
import Debug::*;


module mkIssue#(Vector#(rs_count, ReservationStationIFC#(e)) rs_vec, RobIFC rob, RegFileEvoIFC rf)(IssueIFC) provisos(
    Log#(ROBDEPTH, size_logidx_t),

    Add#(1, ISSUEWIDTH, issuewidth_pad_t),
    Log#(issuewidth_pad_t, issuewidth_log_t),
    Add#(1, rs_count, rs_count_pad_t),
    Log#(rs_count_pad_t, rs_count_log_t),
    Max#(issuewidth_log_t, rs_count_log_t, issue_amount_t),
    Add#(__a, 1, issue_amount_t),

    Add#(__b, rs_count_log_t, issue_amount_t),
    Add#(__b, issuewidth_log_t, issue_amount_t)
);

function Bool get_rdy(ReservationStationIFC#(e) rs) = rs.free();
function ExecUnitTag get_op_type(ReservationStationIFC#(e) rs) = rs.unit_type();

//wires for transport of incoming instructions
Wire#(Vector#(ISSUEWIDTH, Instruction)) inst_in <- mkWire();
Wire#(MIMO::LUInt#(ISSUEWIDTH)) inst_in_cnt <- mkWire();

//gather ready signals
let rdy_inst_vec = Vector::map(get_rdy   , rs_vec);
let op_type_vec = Vector::map(get_op_type, rs_vec);
let rs_free_type_vec = Vector::zip(op_type_vec, rdy_inst_vec);

//get next indices
function UInt#(rob_addr_t) generate_tag(UInt#(rob_addr_t) base, Integer i) = base + fromInteger(i);
Vector#(ISSUEWIDTH, UInt#(size_logidx_t)) rob_entry_idx_v = Vector::genWith(generate_tag(rob.current_idx()));

//wires for transporting parts
Wire#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) gathered_operands <- mkWire();
Vector#(TMul#(2, ISSUEWIDTH), RWire#(UInt#(size_logidx_t))) cross_dependant_operands <- replicateM(mkRWire());
Wire#(UInt#(issuewidth_log_t)) possible_issue_amount <- mkWire();
Wire#(Vector#(ISSUEWIDTH, UInt#(rs_count_log_t))) needed_rs_idx_w <- mkWire();

rule gather_operands;
    let instructions = inst_in;

    Vector#(TMul#(2, ISSUEWIDTH), RADDR) request_addrs;

    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
        request_addrs[2*i] = inst_in[i].rs1.Raddr;
        request_addrs[2*i+1] = inst_in[i].rs2.Raddr;
    end

    gathered_operands <= rf.read_regs(request_addrs);
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
                inst_in[i].rs1 matches tagged Raddr .rs1_addr &&&
                rd_addr == rs1_addr &&& !found_rs1 )
                begin
                    cross_dependant_operands[2*i].wset(rob_entry_idx_v[j-1]);
                    found_rs1 = True;
                end
            //check rs2
            if(inst_in[j-1].rd matches tagged Raddr .rd_addr &&& 
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
function UInt#(rs_count_log_t) find_nth(UInt#(rs_count_log_t) num, Tuple2#(ExecUnitTag, Bool) cmp, Vector#(rs_count, Tuple2#(ExecUnitTag, Bool)) vec);
    UInt#(rs_count_log_t) found = 0;
    UInt#(rs_count_log_t) out = ?;
    for(Integer i = 0; i < valueOf(rs_count); i = i + 1) begin
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

        needed_rs_idx[i] = find_nth(need_issue_cnt, tuple2(instructions[i].eut, True), rs_free_type_vec);

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
    UInt#(ISSUEWIDTH) rob_avail = truncate(rob.free());
    let rob_av_ext = rob.free();
    UInt#(ISSUEWIDTH) rs_avail = truncate(max_issue_rs);

    UInt#(ISSUEWIDTH) max_issue = (extend(max_issue_rs) > rob_av_ext ? rob_avail : rs_avail);

    possible_issue_amount <= max_issue > inst_in_cnt ? inst_in_cnt : max_issue;

    needed_rs_idx_w <= needed_rs_idx;

    dbg_print(Issue, $format("possible issue (rs): ", max_issue_rs));
    dbg_print(Issue, $format("possible issue (rob): ", rob_av_ext));
    dbg_print(Issue, $format("possible issue (inst_in): ", inst_in_cnt));

endrule

function RobEntry map_to_rob_entry(Inst_Types::Instruction inst, UInt#(size_logidx_t) idx);
    return RobEntry {
        pc : inst.pc,
        destination : inst.rd.Raddr,
        result : (isValid(inst.exception) ?
            tagged Except fromMaybe(?, inst.exception) :
            tagged Tag idx)
    };
endfunction

rule reserve_rob;
    let rob_entries = Vector::map(uncurry(map_to_rob_entry), Vector::zip(inst_in, rob_entry_idx_v));
    rob.reserve(rob_entries, possible_issue_amount);
endrule


function RegReservation inst_to_regres(Instruction ins, UInt#(size_logidx_t) idx) 
    = RegReservation { addr : (ins.rd matches tagged Raddr .rd ? rd : 0), tag: idx };
rule set_regfile_tags;
    let reservations = Vector::map(uncurry(inst_to_regres), Vector::zip(inst_in, rob_entry_idx_v));

    rf.set_tags(reservations, possible_issue_amount);
endrule

rule assemble_instructions;
    Vector#(ISSUEWIDTH, Instruction) instructions = inst_in;

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
    Vector#(rs_count, Bool) active_rs = replicate(False);
    Vector#(rs_count, Instruction) instructions_rs = ?;

    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i = i+1) begin
        if(fromInteger(i) < possible_issue_amount) begin
            active_rs[needed_rs_idx_w[i]] = True;
            instructions_rs[needed_rs_idx_w[i]] = instructions[i];
        end
    end

    //now issue
    for(Integer i = 0; i < valueOf(rs_count); i = i+1) begin
        if(active_rs[i] == True) begin
            rs_vec[i].put(instructions_rs[i]);
            dbg_print(Issue, $format("enqueue to RS"));
        end
    end

endrule

method Action put(Vector#(ISSUEWIDTH, Instruction) instructions, MIMO::LUInt#(ISSUEWIDTH) amount);
    inst_in <= instructions;
    inst_in_cnt <= amount;
    dbg_print(Issue, $format("got ", amount, "instructions"));
    dbg_print(Issue, $format(fshow(instructions)));
endmethod

method MIMO::LUInt#(ISSUEWIDTH) remove;
    return possible_issue_amount;
endmethod

endmodule


endpackage