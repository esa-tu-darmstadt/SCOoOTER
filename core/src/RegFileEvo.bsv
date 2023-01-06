package RegFileEvo;

import Inst_Types::*;
import Types::*;
import Vector::*;
import Interfaces::*;
import TestFunctions::*;

// Union for holding data in the evolving RegFile
// The evolving RegFile stores which tag corresponds to
// which arch register currently and stores values
// which were not yet committed
typedef union tagged {
    UInt#(TLog#(ROBDEPTH)) Tag;
    Bit#(XLEN) Value;
    void Invalid;
} EvoEntry deriving(Bits, Eq, FShow);

module mkRegFileEvo#(Vector#(size_res_bus_t, Maybe#(Result)) result_bus_vec)(RegFileEvoIFC);

    Vector#(31, Array#(Reg#(EvoEntry))) registers <- replicateM(mkCReg(3, tagged Invalid));
    //derived Reg ifaces from CReg
    Vector#(31, Reg#(EvoEntry)) registers_port0 = Vector::map(disassemble_creg(0), registers);
    Vector#(31, Reg#(EvoEntry)) registers_port1 = Vector::map(disassemble_creg(1), registers);
    Vector#(31, Reg#(EvoEntry)) registers_port2 = Vector::map(disassemble_creg(2), registers);

    Wire#(Vector#(31, Bit#(XLEN))) arch_regs_wire <- mkWire();

    Reg#(UInt#(XLEN)) epoch <- mkReg(0);

    //sniff from result bus
    rule result_bus;
        Vector#(31, EvoEntry) local_entries = Vector::readVReg(registers_port0);
        
        //for every result
        for(Integer i = 0; i < valueOf(size_res_bus_t); i=i+1) begin
            //if the result is valid
            if(result_bus_vec[i] matches tagged Valid .result) begin
                //find its tag in the regfile
                EvoEntry compare_to = tagged Tag result.tag;
                let idx = Vector::findElem(compare_to, local_entries);
                //and update the value if the tag exists
                if(idx matches tagged Valid .register) begin
                    local_entries[register] = tagged Value result.result.Result;
                end
            end
        end

        Vector::writeVReg(registers_port0, local_entries);
    endrule

    //set the correct tag corresponding to a register
    method Action set_tags(Vector#(ISSUEWIDTH, RegReservation) reservations, Vector#(ISSUEWIDTH, UInt#(XLEN)) epochs, UInt#(TLog#(TAdd#(1, ISSUEWIDTH))) num);
        action
            Vector#(31, EvoEntry) local_entries = Vector::readVReg(registers_port1);
            
            //for every request from issue logic
            for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                if(epochs[i] == epoch) begin
                    let reg_addr = reservations[i].addr;
                    //if the instruction and reg is valid
                    if(fromInteger(i) < num && reg_addr != 0) begin
                        //store the tag to the regfile
                        let tag = reservations[i].tag;
                        local_entries[reg_addr-1] = tagged Tag tag;
                    end
                end
            end

            Vector::writeVReg(registers_port1, local_entries);
        endaction
    endmethod

    //read 2 regs per instruction
    method Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) read_regs(Vector#(TMul#(2, ISSUEWIDTH), RADDR) reg_addrs);
        Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) response;
        Vector#(31, Bit#(XLEN)) committed_regs = arch_regs_wire;

        for (Integer i = 0; i < valueOf(ISSUEWIDTH)*2; i=i+1) begin
            let reg_addr = reg_addrs[i];
            let entry = registers_port1[reg_addr-1];

            response[i] = reg_addr == 0 ? tagged Value 0 : case (entry) matches
                tagged Invalid  : tagged Value committed_regs[reg_addr];
                tagged Tag .t   : tagged Tag t;
                tagged Value .v : tagged Value v;
            endcase;
        end

        return response;
    endmethod
    //input the architectural registers post-commit
    method Action committed_state(Vector#(31, Bit#(XLEN)) regs);
        action
            arch_regs_wire <= regs;
        endaction
    endmethod
    //inform about misprediction
    method Action flush();
        action
            for(Integer i = 0; i < 31; i=i+1)
                registers_port2[i] <= tagged Invalid;
        endaction
    endmethod
endmodule

endpackage