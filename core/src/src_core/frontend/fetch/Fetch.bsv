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
import TestFunctions::*;

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkFetch(FetchIFC) provisos(
        Mul#(XLEN, IFUINST, ifuwidth), //the width of the IFU axi must be as large as the size of a word times the issuewidth
        Log#(NUM_THREADS, thread_id_t)
);

    // open files for pipeline logging
    `ifdef LOG_PIPELINE
        Reg#(UInt#(XLEN)) clk_ctr <- mkReg(0);
        Reg#(File) out_log <- mkRegU();
        Reg#(File) out_log_ko <- mkRegU();
        rule count_clk; clk_ctr <= clk_ctr + 1; endrule
        rule init if (clk_ctr == 0);
            File out_log_f <- $fopen("scoooter.log", "w");
            $fflush();
            File out_log_l <- $fopen("scoooter.log", "a");
            out_log <= out_log_l;

            File out_log_kof <- $fopen("konata.log", "w");
            $fflush();
            File out_log_kol <- $fopen("konata.log", "a");
            out_log_ko <= out_log_kol;
        endrule
    `endif

    // request/response forwarding to memory infrastructure
    FIFO#(Bit#(XLEN)) request_mem_f <- mkBypassFIFO();
    FIFO#(Bit#(ifuwidth)) response_mem_f <- mkBypassFIFO();

    // instantiate RAS per thread
    Vector#(NUM_THREADS, RASIfc) ras <- replicateM(mkRAS());

    //pc points to next instruction to load
    //pc is a CREG, port 2 is used for fetching the next instruction
    // port 1 is used to redirect the program counter
    //port 0 is used to advance the PC
    Vector#(NUM_THREADS, Array#(Reg#(Bit#(PCLEN)))) pc <- replicateM(mkCReg(3, fromInteger(valueof(RESETVEC)/4)));
    // epoch per thread
    Vector#(NUM_THREADS, Reg#(UInt#(EPOCH_WIDTH))) epoch <- replicateM(mkReg(0));
    // store data for in-flight requests to memory
    FIFOF#(Bit#(PCLEN)) inflight_pcs <- mkSizedFIFOF(8);
    FIFOF#(UInt#(EPOCH_WIDTH)) inflight_epoch <- mkSizedFIFOF(8);
    FIFOF#(UInt#(thread_id_t)) inflight_thread <- mkSizedFIFOF(8);
    // local epoch for flushing erroneously-fetched instructions
    Vector#(NUM_THREADS, Reg#(UInt#(3))) local_epoch <- replicateM(mkReg(0));
    FIFOF#(UInt#(3)) inflight_local_epoch <- mkSizedFIFOF(8);
    //holds outbound Instruction s and count
    FIFOF#(Vector#(IFUINST, FetchedInstruction)) fetched_inst <- mkPipelineFIFOF();
    FIFOF#(MIMO::LUInt#(IFUINST)) fetched_amount <- mkPipelineFIFOF();

    // wires for direction prediction response and request
    Vector#(IFUINST, Wire#(Tuple2#(Bit#(PCLEN), Bool))) dir_request_w_v <- replicateM(mkWire());
    Vector#(IFUINST, Wire#(Prediction)) dir_resp_w_v <- replicateM(mkDWire(Prediction {history: ?, pred: False}));
    // wires for target prediction response and request
    FIFO#(Bit#(PCLEN)) target_request_f <- mkBypassFIFO();
    FIFOF#(Vector#(IFUINST, Maybe#(Bit#(PCLEN)))) target_resp_f <- mkSizedFIFOF(8);

    // change thread to fetch for every cycle
    Reg#(UInt#(thread_id_t)) current_thread_r <- mkReg(0);
    rule advance_thread;
        if (ispwr2(valueOf(NUM_THREADS)))
            current_thread_r <= current_thread_r+1;
        else
            current_thread_r <= (current_thread_r == fromInteger(valueOf(NUM_THREADS)-1) ? 0 : (current_thread_r+1));
    endrule

    //Requests data from memory
    //Implicit condition: Fires if the previous read has been evaluated
    // Due to the PC FIFO
    rule requestRead;
        // addr to AXI
        request_mem_f.enq({pc[current_thread_r][0], 2'b00});
        // store data for in-flight memory request
        inflight_pcs.enq(pc[current_thread_r][0]);
        inflight_epoch.enq(epoch[current_thread_r]);
        inflight_local_epoch.enq(local_epoch[current_thread_r]);
        inflight_thread.enq(current_thread_r);
        // request target prediction
        target_request_f.enq(pc[current_thread_r][0]);
        // advance PC
        if (ispwr2(valueOf(IFUINST)))
            pc[current_thread_r][0] <= (pc[current_thread_r][0] & ~(fromInteger(valueOf(IFUINST)-1))) + fromInteger(valueOf(IFUINST));
        else begin
            let overlap = (pc[current_thread_r][0])%fromInteger(valueOf(IFUINST));
            pc[current_thread_r][0] <= pc[current_thread_r][0]-(overlap)+fromInteger(valueOf(IFUINST));
        end
        dbg_print(Fetch, $format("request: ", fshow(pc[current_thread_r][0])));
    endrule

    // if the epoch has changed, drop read data
    rule dropReadResp (inflight_epoch.first() != epoch[inflight_thread.first()] || inflight_local_epoch.first() != local_epoch[inflight_thread.first()]);
        let r = response_mem_f.first(); response_mem_f.deq();
        inflight_pcs.deq();
        inflight_epoch.deq();
        inflight_thread.deq();
        inflight_local_epoch.deq();
        dbg_print(Fetch, $format("drop read"));
        target_resp_f.deq();
    endrule

    //if we cannot predict a direction, fall back on untaken
    function Maybe#(Bit#(PCLEN)) guard_unnknown_targets(Wire#(Prediction) p, Maybe#(Bit#(PCLEN)) target);
        if (target matches tagged Valid .t &&& p.pred)
            return tagged Valid t;
        else return tagged Invalid;
    endfunction

    // wire to pass incoming word
    Wire#(Bit#(ifuwidth)) pass_incoming_w <- mkWire();

    // predict directions
    rule get_dir_pred if (inflight_epoch.first() == epoch[inflight_thread.first()] &&
                        inflight_local_epoch.first() == local_epoch[inflight_thread.first()] &&
                        target_resp_f.notEmpty() &&
                        inflight_pcs.notEmpty() &&
                        fetched_inst.notFull() &&
                        fetched_amount.notFull()
                        );
        // get instruction words
        let r = response_mem_f.first(); response_mem_f.deq();
        pass_incoming_w <= r;

        // get target preds
        let acqpc = inflight_pcs.first();
        let tar_predictions = target_resp_f.first();

        // info for instruction slicing
        Bit#(PCLEN) startpoint = (acqpc)%fromInteger(valueOf(IFUINST))*32;
        MIMO::LUInt#(IFUINST) count_read = unpack(truncate( fromInteger(valueOf(IFUINST)) - (acqpc)%fromInteger(valueOf(IFUINST))));

        // request predictions
        for(Integer i = 0; i < valueOf(IFUINST); i=i+1) begin
            if(fromInteger(i) < count_read) begin
                Bit#(XLEN) iword = r[startpoint+fromInteger(i)*32+31 : startpoint+fromInteger(i)*32];
                // if is branch inst
                if(iword[6:0] == 7'b1100011) begin
                    dir_request_w_v[i] <= tuple2(acqpc + fromInteger(i), isValid(tar_predictions[i]));
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
    rule getReadResp (inflight_epoch.first() == epoch[inflight_thread.first()] && inflight_local_epoch.first() == local_epoch[inflight_thread.first()]);        
        target_resp_f.deq();
        inflight_epoch.deq();
        inflight_local_epoch.deq();
        inflight_thread.deq();

        let acqpc = inflight_pcs.first(); inflight_pcs.deq();

        Vector#(IFUINST, FetchedInstruction) instructions_v = newVector; // temporary inst storage
        
        Bit#(PCLEN) startpoint = (acqpc)%fromInteger(valueOf(IFUINST))*32; // pos of first useful instruction

        MIMO::LUInt#(IFUINST) count_read = unpack(truncate( fromInteger(valueOf(IFUINST)) - (acqpc)%fromInteger(valueOf(IFUINST)))); // how many inst were usefully extracted // TODO: make type smaller

        // predict branches with unknown targets as untaken
        Vector#(IFUINST, Maybe#(Bit#(PCLEN))) cleaned_predictions = Vector::map(uncurry(guard_unnknown_targets), Vector::zip(dir_resp_w_v, target_resp_f.first()));
        // Extract instructions
        for(Integer i = 0; i < valueOf(IFUINST); i=i+1) begin
            if(fromInteger(i) < count_read) begin
                Bit#(XLEN) iword = pass_incoming_w[startpoint+fromInteger(i)*32+31 : startpoint+fromInteger(i)*32];
                // RAS prediction
                if(valueOf(USE_RAS) == 1) begin
                    // CALL /RETURN instructions
                    if(iword[6:0] == 7'b1100111 || iword[6:0] == 7'b1101111) begin
                        // ask RAS
                        let res <- ras[inflight_thread.first()].ports[i].push_pop(check_push(iword) ? tagged Valid (acqpc + (fromInteger(i+1))) : tagged Invalid, check_pop(iword));
                        // if prediction is provided, update the predicted targets
                        if (isValid(res)) cleaned_predictions[i] = res;
                        else cleaned_predictions[i] = target_resp_f.first()[i];
                    end
                end
                // pass instructions on to decode
                instructions_v[i] = FetchedInstruction { 
                    instruction: iword,
                    pc: acqpc + (fromInteger(i)),
                    epoch: inflight_epoch.first(),
                    next_pc: isValid(cleaned_predictions[i]) ? cleaned_predictions[i].Valid : (acqpc + (fromInteger(i)) + 1),
                    history: dir_resp_w_v[i].history,
                    ras: ras[inflight_thread.first()].ports[i].extra(),
                    `ifdef LOG_PIPELINE
                        log_id: (pack(clk_ctr)<<valueof(TLog#(IFUINST)) | fromInteger(i)),
                    `endif
                    thread_id: inflight_thread.first()};
            end
        end

        // enq gathered instructions
        fetched_inst.enq(instructions_v);

        dbg_print(Fetch, $format("got: ", fshow(instructions_v)));

        // check how many instructions are correct path according to prediction
        let count_pred = Vector::findIndex(isValid, cleaned_predictions);

        MIMO::LUInt#(IFUINST) amount;
        // set fetch amount and update PC
        if(count_pred matches tagged Valid .c &&& extend(c) < count_read) begin
            // update PC
            pc[inflight_thread.first()][1] <= truncateLSB(cleaned_predictions[c].Valid);
            // on redirect, update local epoch
            local_epoch[inflight_thread.first()] <= local_epoch[inflight_thread.first()]+1;
            amount = extend(c)+1;
        end else begin
            amount = count_read;
        end
        // pass amount to decode
        fetched_amount.enq(amount);

        `ifdef LOG_PIPELINE
            for(Integer i = 0; i < valueOf(IFUINST); i=i+1) begin
                if(fromInteger(i) < amount) begin
                    $fdisplay(out_log, "%d FETCH %x %x %d", clk_ctr, {instructions_v[i].pc, 2'b00}, instructions_v[i].instruction, instructions_v[i].epoch);
                    $fflush(out_log);
                    $fdisplay(out_log_ko, "%d I %d %d %d", clk_ctr, instructions_v[i].log_id, 0, instructions_v[i].thread_id);
                    $fdisplay(out_log_ko, "%d S %d %d %s", clk_ctr, instructions_v[i].log_id, 0, "F");
                    $fflush(out_log_ko);
                end
            end
        `endif
                
    endrule

    // redirect PC from backend if mispredicted
    Vector#(NUM_THREADS, Wire#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) redirected <- replicateM(mkWire());
    for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1)
        rule redirect_write_pc;
            pc[i][2] <= tpl_1(redirected[i]);
            ras[i].redirect(tpl_2(redirected[i]));
        endrule

    // interface for direction prediction requests
    Vector#(IFUINST, Client#(Tuple2#(Bit#(PCLEN), Bool), Prediction)) pred_ifc = ?;
    for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
        pred_ifc[i] = (interface Client;
            interface Get request;
                method ActionValue#(Tuple2#(Bit#(PCLEN), Bool)) get();
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
    method Action redirect(Vector#(NUM_THREADS, Maybe#(Tuple2#(Bit#(PCLEN), Bit#(RAS_EXTRA)))) in);
        for(Integer i = 0; i < valueOf(NUM_THREADS); i=i+1) if (in[i] matches tagged Valid .v) begin
            redirected[i] <= v;
            dbg_print(Fetch, $format("Redirected: ", tpl_1(v)));
            epoch[i] <= epoch[i]+1;
        end
    endmethod
    
    // output instructions
    interface GetS instructions;
        method FetchResponse first();
            let inst_vector = fetched_inst.first();
            let fetched_inst = inst_vector;
            return FetchResponse {count: fetched_amount.first(), instructions: fetched_inst};
        endmethod
        method Action deq();
            fetched_inst.deq();
            fetched_amount.deq();
        endmethod
    endinterface

    // interface to memory
    interface Client read;
        interface Get request = toGet(request_mem_f);
        interface Put response = toPut(response_mem_f);
    endinterface

    // output currently handled thread
    method UInt#(TLog#(NUM_THREADS)) current_thread() = current_thread_r._read();
endmodule

endpackage