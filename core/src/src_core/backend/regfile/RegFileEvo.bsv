package RegFileEvo;

import Inst_Types::*;
import Types::*;
import Vector::*;
import Interfaces::*;
import TestFunctions::*;
import Debug::*;
import ClientServer::*;
import GetPut::*;

// Union for holding data in the evolving RegFile
// The evolving RegFile stores which tag corresponds to
// which arch register currently and stores values
// which were not yet committed
typedef union tagged {
    UInt#(TLog#(ROBDEPTH)) Tag;
    Bit#(XLEN) Value;
    void Invalid;
} EvoEntry deriving(Bits, Eq, FShow);

(* synthesize *)
module mkRegFileEvo(RegFileEvoIFC);

    // wire for distributing the result bus
    Wire#(Vector#(NUM_FU, Maybe#(Result))) result_bus_vec <- mkWire();

    //register storage
    Vector#(31, Array#(Reg#(EvoEntry))) registers <- replicateM(mkCReg(3, tagged Invalid));
    //derived Reg ifaces from CReg
    Vector#(31, Reg#(EvoEntry)) registers_port0 = Vector::map(disassemble_creg(0), registers);
    Vector#(31, Reg#(EvoEntry)) registers_port1 = Vector::map(disassemble_creg(1), registers);
    Vector#(31, Reg#(EvoEntry)) registers_port2 = Vector::map(disassemble_creg(2), registers);

    Wire#(Vector#(31, Bit#(XLEN))) arch_regs_wire <- mkWire();

    Reg#(UInt#(XLEN)) epoch <- mkReg(0);


    function Bool test_result(UInt#(TLog#(ROBDEPTH)) current_tag, Maybe#(Result) res);
        return (res matches tagged Valid .res_v &&& res_v.tag == current_tag ? True : False);
    endfunction
    //sniff from result bus
    rule result_bus_r;
        Vector#(31, EvoEntry) local_entries = Vector::readVReg(registers_port0);

        for(Integer i = 0; i < 31; i=i+1) begin
            let current_entry = local_entries[i];

            if(current_entry matches tagged Tag .current_tag) begin
                let result = Vector::find(test_result(current_tag), result_bus_vec);
                if(result matches tagged Valid .found_result) begin
                    local_entries[i] = tagged Value found_result.Valid.result.Result;
                    dbg_print(RegEvo, $format("Setting reg ", i+1, found_result.Valid.result.Result));
                end
            end
        end

        Vector::writeVReg(registers_port0, local_entries);
    endrule

    Wire#(Vector#(ISSUEWIDTH, RegReservation)) reservations_w <- mkWire();
    Wire#(UInt#(TLog#(TAdd#(1, ISSUEWIDTH)))) num_w <- mkWire();
    Wire#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) register_responses_w <- mkWire();

    PulseWire clear_w <- mkPulseWire();

    rule set_tags_r;
        Vector#(31, EvoEntry) local_entries = Vector::readVReg(registers_port1);
            
        //for every request from issue logic
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            if(reservations_w[i].epoch == epoch) begin
                let reg_addr = reservations_w[i].addr;
                //if the instruction and reg is valid
                if(fromInteger(i) < num_w && reg_addr != 0) begin
                    //store the tag to the regfile
                    let tag = reservations_w[i].tag;
                    local_entries[reg_addr-1] = tagged Tag tag;
                    dbg_print(RegEvo, $format("Setting tag: ", reg_addr, tag));
                end
            end
        end

        Vector::writeVReg(registers_port1, local_entries);
    endrule

    rule clear_r(clear_w);
        Vector::writeVReg(registers_port2, replicate(tagged Invalid));
        epoch <= epoch+1;
    endrule

    rule print_debug;
        for(Integer i = 0; i < 31; i=i+1)
            dbg_print(RegEvo, $format(i+1, ": ", fshow(registers_port1[i]), " ", arch_regs_wire[i]));
    endrule

    //input the architectural registers post-commit
    method Action committed_state(Vector#(31, Bit#(XLEN)) regs);
        action
            arch_regs_wire <= regs;
        endaction
    endmethod

    //inform about misprediction
    method Action flush();
        clear_w.send();
    endmethod

    method Action result_bus(Vector#(NUM_FU, Maybe#(Result)) bus_in);
        result_bus_vec <= bus_in;
    endmethod

    interface Server read_registers;
    
        interface Put request;
            method Action put(Vector#(TMul#(2, ISSUEWIDTH), RADDR) req);
                Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) response;
                Vector#(31, Bit#(XLEN)) committed_regs = arch_regs_wire;

                for (Integer i = 0; i < valueOf(ISSUEWIDTH)*2; i=i+1) begin
                    let reg_addr = req[i];
                    let entry = registers_port1[reg_addr-1];

                    response[i] = (reg_addr == 0 ? tagged Value 0 : case (entry) matches
                        tagged Invalid  : tagged Value committed_regs[reg_addr-1];
                        tagged Tag .t   : tagged Tag t;
                        tagged Value .v : tagged Value v;
                        endcase);
                end

                register_responses_w <= response;
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) get();
                actionvalue
                    return register_responses_w;
                endactionvalue
            endmethod
        endinterface
    
    endinterface
    
    interface Put reserve_registers;
        method Action put(RegReservations in);
            action
                reservations_w <= in.reservations;
                num_w <= in.count;
            endaction
        endmethod
    endinterface
endmodule

endpackage