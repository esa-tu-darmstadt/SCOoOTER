package MemoryArbiter;

import BlueAXI::*;
import Types::*;
import Inst_Types::*;
import GetPut::*;
import ClientServer::*;
import Interfaces::*;
import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Debug::*;
import Vector::*;
import MIMO::*;
import Ehr::*;

// types
    typedef struct {
        Bit#(XLEN) addr;
        Maybe#(Tuple2#(Bit#(XLEN), AmoType)) amo_data_and_type;
        Bit#(TLog#(NUM_CPU)) cpu_id;
    } Rd_or_amo_req deriving(Bits, Eq, FShow);


`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkMemoryArbiter(MemoryArbiterIFC) provisos (
    Log#(NUM_CPU, idx_cpu_t),
    Mul#(NUM_CPU, 2, num_by_two_cpu_t),
    Add#(idx_cpu_t, 1, axi_idx_t)
);

    //Buffers for rq/rs
    FIFO#(Tuple2#(UInt#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) rd_rq_fifo <- mkPipelineFIFO();
    FIFO#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) rd_rs_fifo <- mkPipelineFIFO();
    FIFO#(Tuple4#(UInt#(XLEN), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) wr_rq_fifo <- mkPipelineFIFO();
    FIFO#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) wr_rs_fifo <- mkPipelineFIFO();

    //request buffers
    Vector#(NUM_CPU, FIFO#(Bit#(XLEN))) mem_rd_resp_f_v <- replicateM(mkPipelineFIFO());

    //load/store queues
    MIMO#(NUM_CPU, 1, num_by_two_cpu_t, Rd_or_amo_req) load_queue <- mkMIMO(defaultValue);
    MIMO#(NUM_CPU, 1, num_by_two_cpu_t, Tuple2#(MemWr, Bit#(idx_cpu_t))) store_queue <- mkMIMO(defaultValue);

    // AMO state
    PulseWire amo_notify_wire <- mkPulseWire();
    Reg#(Bool) amo_in_progress <- mkReg(False);
    FIFO#(Tuple4#(Bit#(XLEN), Bit#(XLEN), AmoType, Bit#(idx_cpu_t))) amo_description <- mkPipelineFIFO();
    Reg#(Maybe#(Bit#(XLEN))) link_lrsc <- mkReg(tagged Invalid);

    Wire#(Bit#(XLEN)) result_read <- mkWire();
    Wire#(Bit#(XLEN)) result_amo <- mkWire();
    rule distribute_read_responses;
        let r = rd_rs_fifo.first(); rd_rs_fifo.deq();

        dbg_print(AMO, $format("got AXI response"));
        Bit#(idx_cpu_t) cpu_id = truncate(tpl_2(r));
        Bit#(1) amo_id = truncateLSB(tpl_2(r));
        if (amo_id == 0) mem_rd_resp_f_v[cpu_id].enq(tpl_1(r));
        else             result_amo  <= tpl_1(r);
    endrule

    Vector#(NUM_CPU, PulseWire) result_writes <- replicateM(mkPulseWire());
    PulseWire write_amo <- mkPulseWire();
    rule distribute_write_responses;
        let r = wr_rs_fifo.first(); wr_rs_fifo.deq();
        Bit#(idx_cpu_t) cpu_id = truncate(r);
        Bit#(1) amo_id = truncateLSB(r);
        if (amo_id == 0) result_writes[cpu_id].send();
        else           write_amo.send();
    endrule

    //read/AMO pipe

    // first, acquire all incoming read requests and sort them into the queue
    Ehr#(TAdd#(1, NUM_CPU), MIMO::LUInt#(NUM_CPU)) rd_req_in_count <- mkEhr(0); // state how many inputs were collected

    Vector#(NUM_CPU, Wire#(Rd_or_amo_req)) incoming_inst <- replicateM(mkDWire(?));
    rule reset_count_and_collapse_buffer;
        rd_req_in_count[valueOf(NUM_CPU)] <= 0;
        load_queue.enq(rd_req_in_count[valueOf(NUM_CPU)], Vector::readVReg(incoming_inst));
    endrule

    // implement reading
    rule compute_input if (!amo_in_progress);
        let in = load_queue.first()[0];
        load_queue.deq(1);

        if (isValid(in.amo_data_and_type)) dbg_print(CoherentMem, $format("%x LOAD/AMO: ", in.addr, fshow(in)));

        if(isValid(in.amo_data_and_type)) begin // AMO operation
            amo_notify_wire.send();

            dbg_print(AMO, $format("Arbiter got req:  ", fshow(in)));
            let amo_op = tpl_2(in.amo_data_and_type.Valid);
            let amo_data = tpl_1(in.amo_data_and_type.Valid);

            if(amo_op == LR) begin
                link_lrsc <= tagged Valid in.addr;
            end
                    
            if(amo_op != SC) begin
                amo_description.enq(tuple4(in.addr, amo_data, amo_op, in.cpu_id));
                rd_rq_fifo.enq(tuple2(unpack(in.addr), {1, in.cpu_id}));
                amo_in_progress <= True;

                dbg_print(AMO, $format("Arbiter: request Data"));
            
            end else begin // SC handling

                // calculate failure
                if(link_lrsc matches tagged Valid .v &&& v == in.addr) begin
                    mem_rd_resp_f_v[in.cpu_id].enq(0);
                    // write
                    wr_rq_fifo.enq(tuple4(unpack(in.addr), amo_data, 'hf, {1, in.cpu_id}));
                    amo_in_progress <= True;
                end else begin
                    mem_rd_resp_f_v[in.cpu_id].enq(1);
                    amo_in_progress <= False;
                end

                // invalidate
                link_lrsc <= tagged Invalid;
            end
        end else begin // normal operation
            rd_rq_fifo.enq(tuple2(unpack(in.addr), {0, in.cpu_id}));
        end
    endrule

    //since both rules may write the output FIFO, we must tell the compiler
    //that in any clock cycloe only one of them does
    (* conflict_free = "distribute_read_responses, amo_transform_data" *)
    rule amo_transform_data if (amo_in_progress && !write_amo);
        dbg_print(AMO, $format("transform AMO"));
        let read_data = result_amo;
        amo_description.deq();
        let mod_data = tpl_2(amo_description.first());
        UInt#(XLEN) mod_data_u = unpack(mod_data);
        Int#(XLEN) mod_data_s = unpack(mod_data);
        UInt#(XLEN) read_data_u = unpack(read_data);
        Int#(XLEN) read_data_s = unpack(read_data);

        let write_data = case (tpl_3(amo_description.first()))
            ADD:   (read_data + mod_data);
            SWAP:  (mod_data);
            AND:   (read_data & mod_data);
            OR:    (read_data | mod_data);
            XOR:   (read_data ^ mod_data);
            MAX:   pack(max(read_data_s, mod_data_s));
            MIN:   pack(min(read_data_s, mod_data_s));
            MAXU:  pack(max(read_data_u, mod_data_u));
            MINU:  pack(min(read_data_u, mod_data_u));
        endcase;

        mem_rd_resp_f_v[tpl_4(amo_description.first())].enq(read_data);

        if (tpl_3(amo_description.first()) != LR) begin
            wr_rq_fifo.enq(tuple4(unpack(tpl_1(amo_description.first())), write_data, 'hf, {1, tpl_4(amo_description.first())}));
            dbg_print(AMOTrace, $format("AMO: ", fshow(tpl_1(amo_description.first())), " ", fshow(tpl_3(amo_description.first())), " ", fshow(read_data), " ", fshow(mod_data), " ", fshow(write_data)));
        end else begin
            amo_in_progress <= False;
        end
    endrule

    rule resume_normal_operation_after_amo if (amo_in_progress && write_amo);
        amo_in_progress <= False;
    endrule

    // store pipe

    // first, acquire all incoming read requests and sort them into the queue
    Ehr#(TAdd#(1, NUM_CPU), MIMO::LUInt#(NUM_CPU)) st_req_in_count <- mkEhr(0); // state how many outputs were collected

    Vector#(NUM_CPU, Wire#(Tuple2#(MemWr, Bit#(idx_cpu_t)))) incoming_store <- replicateM(mkDWire(?));
    rule reset_count_and_collapse_store_buffer;
        st_req_in_count[valueOf(NUM_CPU)] <= 0;
        store_queue.enq(st_req_in_count[valueOf(NUM_CPU)], Vector::readVReg(incoming_store));
    endrule

    rule elapse_store_op if (!amo_notify_wire && !amo_in_progress);
        let in = store_queue.first()[0];
        let write = tpl_1(in);
        let cpu_id = tpl_2(in);
        store_queue.deq(1);

        dbg_print(WriteTrace, $format("%x STORE: ", tpl_1(in).mem_addr, fshow(in)));
        
        wr_rq_fifo.enq(tuple4(write.mem_addr, write.data, write.store_mask, {0, cpu_id}));

        if(link_lrsc matches tagged Valid .v &&& v == pack(write.mem_addr))
            link_lrsc <= tagged Invalid;
    endrule

    // read request interface
    // provide incoming data in order for reset_count_and_collapse_buffer rule
    Vector#(NUM_CPU, Server#(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType))), Bit#(XLEN))) reads_loc = ?;
    for(Integer i = 0; i < valueOf(NUM_CPU); i=i+1) begin
        reads_loc[i] = (interface Server;
            interface Put request;
                method Action put(Tuple2#(Bit#(XLEN), Maybe#(Tuple2#(Bit#(XLEN), AmoType))) in) if (load_queue.enqReadyN(rd_req_in_count[i]+1));
                    rd_req_in_count[i] <= rd_req_in_count[i]+1;
                    incoming_inst[rd_req_in_count[i]] <= Rd_or_amo_req {addr: tpl_1(in), amo_data_and_type: tpl_2(in), cpu_id: fromInteger(i)};
                endmethod
            endinterface
            interface Get response = toGet(mem_rd_resp_f_v[i]);
        endinterface);
    end

    // normal writes
    Vector#(NUM_CPU, Server#(MemWr, void)) writes_loc = ?;
    for(Integer i = 0; i < valueOf(NUM_CPU); i=i+1) begin
        writes_loc[i] = (interface Server;
            interface Put request;
                method Action put(MemWr write) if (store_queue.enqReadyN(rd_req_in_count[i]+1));
                    st_req_in_count[i] <= st_req_in_count[i]+1;
                    incoming_store[st_req_in_count[i]] <= tuple2(write, fromInteger(i));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(void) get() if (result_writes[i]);
                    return ?;
                endmethod
            endinterface
        endinterface);
    end

    interface reads = reads_loc;
    interface writes = writes_loc;

    // connection to data memory
    interface Client dmem_r;
        interface Get request = toGet(rd_rq_fifo);
        interface Put response = toPut(rd_rs_fifo);
    endinterface
    interface Client dmem_w;
        interface Get request = toGet(wr_rq_fifo);
        interface Put response = toPut(wr_rs_fifo);
    endinterface

endmodule

endpackage
