package RegFileEvo;

/*
  This regfile tracks the SPECULATIVE register state.

  The regfile stores Tags, if the value for this register is
  still in calculation.
  If a value was produced, it stores this value.
  If a flush occured or we are just starting, the Regfile
  contains None - this informs ISSUE that it needs to look
  at the architectural registers.
*/

import Inst_Types::*;
import Types::*;
import Vector::*;
import Interfaces::*;
import TestFunctions::*;
import Debug::*;
import ClientServer::*;
import GetPut::*;
import Ehr::*;
import ArianeEhr::*;

// Union for holding data in the evolving RegFile
// The evolving RegFile stores which tag corresponds to
// which arch register currently and stores values
// which were not yet committed
typedef union tagged {
    UInt#(TLog#(ROBDEPTH)) Tag;
    Bit#(XLEN) Value;
    void Invalid;
} EvoEntry deriving(Bits, Eq, FShow);

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkRegFileEvo(RegFileEvoIFC);

    // wire for distributing the result bus
    Wire#(Vector#(NUM_FU, Maybe#(ResultLoopback))) result_bus_vec <- mkWire();
    // wire to transport read data from request to response
    Wire#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) register_responses_w <- mkWire();

    //register storage
    Vector#(NUM_THREADS, Vector#(31, Ehr#(3, EvoEntry))) registers <- replicateM(replicateM(valueOf(REGEVO_LATCH_BASED) == 0 ? mkEhr(tagged Invalid): mkArianeEhr(tagged Invalid)));
    //derived Reg ifaces from CReg
    Vector#(NUM_THREADS, Vector#(31, Reg#(EvoEntry))) registers_port0 = Vector::map(compose(Vector::map, disassemble_ehr)(0), registers);
    Vector#(NUM_THREADS, Vector#(31, Reg#(EvoEntry))) registers_port1 = Vector::map(compose(Vector::map, disassemble_ehr)(1), registers);
    Vector#(NUM_THREADS, Vector#(31, Reg#(EvoEntry))) registers_port2 = Vector::map(compose(Vector::map, disassemble_ehr)(2), registers);

    //local epoch counter
    Vector#(NUM_THREADS, Reg#(UInt#(EPOCH_WIDTH))) epoch <- replicateM(mkReg(0));

    //helper function: tests if a result matches a given tag
    function Bool test_result(UInt#(TLog#(ROBDEPTH)) current_tag, Maybe#(ResultLoopback) res)
        = (isValid(res) && res.Valid.tag == current_tag);
    
    //evaluate result bus
    rule result_bus_r;

        for(Integer n = 0; n < valueOf(NUM_THREADS); n=n+1) begin

            Vector#(31, EvoEntry) local_entries = Vector::readVReg(registers_port0[n]);

            // for each register, test if it holds a tag and if so,
            // test if the current result bus provides said tag
            for(Integer i = 0; i < 31; i=i+1) begin
                let current_entry = local_entries[i];

                if(current_entry matches tagged Tag .current_tag) begin // reg is tagged
                    let result = Vector::find(test_result(current_tag), result_bus_vec); // find result matching tag
                    if(result matches tagged Valid .found_result) begin // if result exists, update value
                        local_entries[i] = tagged Value found_result.Valid.result;
                        dbg_print(RegEvo, $format("Setting reg ", i+1, found_result.Valid.result));
                    end
                end
            end

            Vector::writeVReg(registers_port0[n], local_entries);

        end
    endrule

    // print the contents 
    rule print_debug;
        for(Integer i = 0; i < 31; i=i+1)
            dbg_print(RegEvo, $format(i+1, ": ", fshow(registers_port1[0][i])));
    endrule

    //inform about misprediction
    method Action flush(Vector#(NUM_THREADS, Bool) flags);
        for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) 
        if(flags[i]) begin
            Vector::writeVReg(registers_port2[i], replicate(tagged Invalid));
            epoch[i] <= epoch[i]+1;
        end
    endmethod

    // read the result bus
    method Action result_bus(Vector#(NUM_FU, Maybe#(ResultLoopback)) bus_in);
        result_bus_vec <= bus_in;
    endmethod

    // server/client for reading
    interface Server read_registers;
    
        interface Put request;
            method Action put(Vector#(TMul#(2, ISSUEWIDTH), RegRead) req);
                Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) response;

                for (Integer i = 0; i < valueOf(ISSUEWIDTH)*2; i=i+1) begin
                    let reg_addr = req[i].addr;
                    let thread_id = req[i].thread_id;
                    let entry = registers_port1[thread_id][reg_addr-1];

                    // if we store a value, return it, otherwise return a Tag.
                    // if we have neither, return None
                    response[i] = (reg_addr == 0 ? tagged Value 0 : case (entry) matches
                        tagged Invalid  : tagged None;
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
                    // broadcast returned result
                    return register_responses_w;
                endactionvalue
            endmethod
        endinterface
    
    endinterface
    
    // set Tags to registers
    interface Put reserve_registers;
        method Action put(RegReservations in);
            action
                Vector#(NUM_THREADS, Vector#(31, EvoEntry)) local_entries = Vector::map(Vector::readVReg, registers_port1);
            
                //for every request from issue logic
                for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                    let thread_id = in.reservations[i].thread_id;
                    if(in.reservations[i].epoch == epoch[thread_id]) begin
                        let reg_addr = in.reservations[i].addr;
                        //if the instruction and register is valid
                        if(in.mask[i] == 1 && reg_addr != 0) begin
                            //store the tag to the regfile
                            let tag = in.reservations[i].tag;
                            local_entries[thread_id][reg_addr-1] = tagged Tag tag;
                            dbg_print(RegEvo, $format("Setting tag: ", reg_addr, tag));
                        end
                    end
                end

                // write data back
                for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
                    Vector::writeVReg(registers_port1[i], local_entries[i]);
            endaction
        endmethod
    endinterface
endmodule


`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkRegFileEvo_dummy(RegFileEvoIFC);
    // wire to transport read data from request to response
    Wire#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) register_responses_w <- mkWire();

    // server/client for reading
    interface Server read_registers;
    
        interface Put request;
            method Action put(Vector#(TMul#(2, ISSUEWIDTH), RegRead) req);
                Vector#(TMul#(2, ISSUEWIDTH), EvoResponse) response;

                for (Integer i = 0; i < valueOf(ISSUEWIDTH)*2; i=i+1) begin
                    let reg_addr = req[i].addr;
                    // if we store a value, return it, otherwise return a Tag.
                    // if we have neither, return None
                    response[i] = (reg_addr == 0 ? tagged Value 0 : tagged None);
                end

                register_responses_w <= response;
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Vector#(TMul#(2, ISSUEWIDTH), EvoResponse)) get();
                actionvalue
                    // broadcast returned result
                    return register_responses_w;
                endactionvalue
            endmethod
        endinterface
    
    endinterface

endmodule


endpackage

