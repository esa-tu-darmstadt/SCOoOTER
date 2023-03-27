package Fetch;

/*
  FETCH gathers instructions from memory and provides them
  to DECODE.
*/

import BlueAXI :: *;
import Types :: *;
import Interfaces :: *;
import GetPut :: *;
import Inst_Types :: *;
import Decode :: *;
import FIFO :: *;
import FIFOF :: *;
import SpecialFIFOs :: *;
import MIMO :: *;
import Vector :: *;
import Debug::*;
import ClientServer::*;
import RAS::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkFetch(FetchIFC) provisos(
        Mul#(XLEN, IFUINST, ifuwidth) //the width of the IFU axi must be as large as the size of a word times the issuewidth
);

    //AXI for mem access
    AXI4_Master_Rd#(XLEN, ifuwidth, 0, 0) axi <- mkAXI4_Master_Rd(0, 0, False);

    RASIfc ras <- mkRAS();
    //pc points to next instruction to load
    //pc is a CREG, port 2 is used for fetching the next instruction
    // port 1 is used to redirect the program counter
    //port 0 is used to advance the PC
    Reg#(Bit#(XLEN)) pc[3] <- mkCReg(3, fromInteger(valueof(RESETVEC)));
    Reg#(UInt#(XLEN)) epoch[2] <- mkCReg(2, 0);
    FIFOF#(Bit#(XLEN)) inflight_pcs <- mkPipelineFIFOF();
    FIFOF#(UInt#(XLEN)) inflight_epoch <- mkPipelineFIFOF();
    //holds outbound Instruction and PC
    FIFOF#(Vector#(IFUINST, Tuple6#(Bit#(32), Bit#(32), UInt#(32), Maybe#(Bit#(XLEN)), Bit#(BITS_BHR), Bit#(RAS_EXTRA)))) fetched_inst <- mkPipelineFIFOF();
    FIFOF#(MIMO::LUInt#(IFUINST)) fetched_amount <- mkPipelineFIFOF();

    // wires for direction prediction response and request
    Vector#(IFUINST, Wire#(Tuple2#(Bit#(XLEN), Bool))) dir_request_w_v <- replicateM(mkWire());
    Vector#(IFUINST, Wire#(Prediction)) dir_resp_w_v <- replicateM(mkDWire(Prediction {history: ?, pred: False}));
    // wires for target prediction response and request
    FIFO#(Bit#(XLEN)) target_request_f <- mkBypassFIFO();
    FIFOF#(Vector#(IFUINST, Maybe#(Bit#(XLEN)))) target_resp_f <- mkBypassFIFOF();

    Reg#(Bit#(32)) c <- mkReg(0);
    rule upd_reg;
        c <= c+1;
    endrule

    //Requests data from memory
    //Explicit condition: Fires if the previous read has been evaluated
    // Due to the PC FIFO
    rule requestRead;
        // addrs to AXI may be weird here
        axi4_read_data(axi, pc[2], 0);
        inflight_pcs.enq(pc[2]);
        inflight_epoch.enq(epoch[1]);
        target_request_f.enq(pc[2]);
    endrule

    // if the epoch has changed, drop read data
    rule dropReadResp (inflight_epoch.first() != epoch[1]);
        let r <- axi.response.get;
        inflight_pcs.deq();
        inflight_epoch.deq();
        dbg_print(Fetch, $format("drop read"));
        target_resp_f.deq();
    endrule

    //if we cannot predict a direction, fall back on untaken
    function Maybe#(Bit#(XLEN)) guard_unnknown_targets(Wire#(Prediction) p, Maybe#(Bit#(XLEN)) target);
        if (target matches tagged Valid .t &&& p.pred)
            return tagged Valid t;
        else return tagged Invalid;
    endfunction

    // wire to pass incoming word
    Wire#(Bit#(ifuwidth)) pass_incoming_w <- mkWire();

    // predict directions
    rule get_dir_pred if (inflight_epoch.first() == epoch[1] &&
                        inflight_epoch.notEmpty() &&
                        target_resp_f.notEmpty() &&
                        inflight_pcs.notEmpty() &&
                        fetched_inst.notFull() &&
                        fetched_amount.notFull()
                        );
        let r <- axi.response.get();
        pass_incoming_w <= r.data;

        let acqpc = inflight_pcs.first();
        let dir_predictions = target_resp_f.first();
        Bit#(XLEN) startpoint = (acqpc>>2)%fromInteger(valueOf(IFUINST))*32;
        MIMO::LUInt#(IFUINST) count_read = unpack(truncate( fromInteger(valueOf(IFUINST)) - (acqpc>>2)%fromInteger(valueOf(IFUINST))));

        // request predictions
        for(Integer i = 0; i < valueOf(IFUINST); i=i+1) begin
            if(fromInteger(i) < count_read) begin
                Bit#(XLEN) iword = r.data[startpoint+fromInteger(i)*32+31 : startpoint+fromInteger(i)*32];
                if(iword[6:0] == 7'b1100011) begin
                    dir_request_w_v[i] <= tuple2(acqpc + fromInteger(i)*4, isValid(dir_predictions[i]));
                end
            end
        end
    endrule

    // check if RAS should be pushed or popped
    function Bool check_pop(Bit#(XLEN) inst_word);
        // check if instruction is a JAL and whether rs1 and rd are link regs
        Bool rs1_lr = inst_word[6:0] != 7'b1101111 && (inst_word[19:15] == 1 || inst_word[19:15] == 5);
        Bool rd_lr = inst_word[11:7] == 1 || inst_word[11:7] == 5;
        Bool rs1_is_rd = inst_word[19:15] == inst_word[11:7];

        return (!rd_lr && rs1_lr) || (!rs1_is_rd && rd_lr && rs1_lr);
    endfunction

    function Bool check_push(Bit#(XLEN) inst_word);
        // check if instruction is a JAL and whether rs1 and rd are link regs
        Bool rs1_lr = inst_word[6:0] != 7'b1101111 && (inst_word[19:15] == 1 || inst_word[19:15] == 5);
        Bool rd_lr = inst_word[11:7] == 1 || inst_word[11:7] == 5;

        return (rd_lr && !rs1_lr) || (rd_lr && rs1_lr);
    endfunction

    // Evaluates fetched instructions if there is enough space in the instruction window
    // TODO: make enqueued value dynamic
    rule getReadResp;        
        target_resp_f.deq();
        inflight_epoch.deq();

        let dir_predictions = target_resp_f.first();

        let acqpc = inflight_pcs.first(); inflight_pcs.deq();

        Vector#(IFUINST, Tuple6#(Bit#(32), Bit#(32), UInt#(XLEN), Maybe#(Bit#(XLEN)), Bit#(BITS_BHR), Bit#(RAS_EXTRA))) instructions_v = newVector; // temporary inst storage
        
        Bit#(XLEN) startpoint = (acqpc>>2)%fromInteger(valueOf(IFUINST))*32; // pos of first useful instruction

        MIMO::LUInt#(IFUINST) count_read = unpack(truncate( fromInteger(valueOf(IFUINST)) - (acqpc>>2)%fromInteger(valueOf(IFUINST)))); // how many inst were usefully extracted // TODO: make type smaller

        Vector#(IFUINST, Maybe#(Bit#(XLEN))) cleaned_predictions = Vector::map(uncurry(guard_unnknown_targets), Vector::zip(dir_resp_w_v, target_resp_f.first()));
        // Extract instructions
        for(Integer i = 0; i < valueOf(IFUINST); i=i+1) begin
            if(fromInteger(i) < count_read) begin
                Bit#(XLEN) iword = pass_incoming_w[startpoint+fromInteger(i)*32+31 : startpoint+fromInteger(i)*32];
                // RAS prediction
                if(valueOf(USE_RAS) == 1) begin
                    if(iword[6:0] == 7'b1100111 || iword[6:0] == 7'b1101111) begin
                        let res <- ras.ports[i].push_pop(check_push(iword) ? tagged Valid (acqpc + (fromInteger(i+1)*4)) : tagged Invalid, check_pop(iword));
                        if (isValid(res)) cleaned_predictions[i] = res;
                        else cleaned_predictions[i] = target_resp_f.first()[i];
                    end
                end
                // pass instructions on
                instructions_v[i] = tuple6(iword, acqpc + (fromInteger(i)*4), inflight_epoch.first(), cleaned_predictions[i], dir_resp_w_v[i].history, ras.ports[i].extra());
                
            end
        end

        // enq gathered instructions
        fetched_inst.enq(instructions_v);

        // check how many instructions are correct path according to prediction
        let count_pred = Vector::findIndex(isValid, cleaned_predictions);

        // set fetch amount and update PC
        if(count_pred matches tagged Valid .c &&& extend(c) < count_read) begin
            pc[0] <= cleaned_predictions[c].Valid;
            fetched_amount.enq(extend(c)+1);
        end else begin
            pc[0] <= acqpc + (pack(extend(count_read)) << 2);
            fetched_amount.enq(count_read);
        end
    endrule

    // redirect PC 
    Wire#(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA))) redirected <- mkWire();
    rule redirect_write_pc;
        pc[1] <= tpl_1(redirected);
        ras.redirect(tpl_2(redirected));
    endrule

    // build fetch response package
    function FetchedInstruction build_fetch_resp(Tuple6#(Bit#(32), Bit#(32), UInt#(XLEN), Maybe#(Bit#(XLEN)), Bit#(BITS_BHR), Bit#(RAS_EXTRA)) in)
        = FetchedInstruction {instruction: tpl_1(in), pc: tpl_2(in), epoch: tpl_3(in), next_pc: fromMaybe(tpl_2(in)+4, tpl_4(in)), history: tpl_5(in), ras: tpl_6(in)};

    // interface for direction prediction requests
    Vector#(IFUINST, Client#(Tuple2#(Bit#(XLEN), Bool), Prediction)) pred_ifc = ?;
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        pred_ifc[i] = (interface Client;
            interface Get request;
                method ActionValue#(Tuple2#(Bit#(XLEN), Bool)) get();
                    actionvalue
                            return dir_request_w_v[i];
                    endactionvalue
                endmethod
            endinterface 
            interface Put response;
                method Action put(Prediction p) = dir_resp_w_v[i]._write(p);
            endinterface
        endinterface);
    end
    interface predict_direction = pred_ifc;

    // interface for target predictions
    interface Client predict_target;
        interface Get request = toGet(target_request_f);
        interface Put response = toPut(target_resp_f);
    endinterface

    // redirect the fetch stage
    method Action redirect(Tuple2#(Bit#(XLEN), Bit#(RAS_EXTRA)) in);
        redirected <= in;
        dbg_print(Fetch, $format("Redirected: ", tpl_1(in)));
        epoch[0] <= epoch[0]+1;
    endmethod
    
    // output instructions
    interface GetS instructions;
        method FetchResponse first();
            let inst_vector = fetched_inst.first();
            let fetched_inst = Vector::map(build_fetch_resp, inst_vector);
            return FetchResponse {count: fetched_amount.first(), instructions: fetched_inst};
        endmethod
        method Action deq();
            fetched_inst.deq();
            fetched_amount.deq();
        endmethod
    endinterface

    interface imem_axi = axi.fab;
endmodule

endpackage