package InstructionArbiter;

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
        Bit#(TLog#(NUM_CPU)) cpu_id;
    } Rd_req deriving(Bits, Eq, FShow);


`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkInstructionArbiter(InstArbiterIFC) provisos (
    Log#(NUM_CPU, idx_cpu_t),
    Mul#(NUM_CPU, 8, num_by_two_cpu_t),
    Mul#(XLEN, IFUINST, ifuwidth)
);

    //AXI modules
    `ifndef SOC
    AXI4_Master_Rd#(XLEN, ifuwidth, idx_cpu_t, 0) axi_rd <- mkAXI4_Master_Rd(0, 0, False);
    `else
    FIFO#(Tuple2#(UInt#(XLEN), Bit#(TLog#(NUM_CPU)))) req_fifo <- mkPipelineFIFO();
    FIFO#(Tuple2#(Bit#(TMul#(XLEN, IFUINST)), Bit#(TLog#(NUM_CPU)))) res_fifo <- mkPipelineFIFO();
    `endif

    //request buffers
    Vector#(NUM_CPU, FIFO#(Bit#(XLEN))) mem_rd_req_f_v <- replicateM(mkPipelineFIFO());
    Vector#(NUM_CPU, FIFO#(Bit#(ifuwidth))) mem_rd_resp_f_v <- replicateM(mkPipelineFIFO());

    //load/store queues
    MIMO#(NUM_CPU, 1, num_by_two_cpu_t, Rd_req) load_queue <- mkMIMO(defaultValue);

    Wire#(Bit#(XLEN)) result_read <- mkWire();
    rule distribute_read_responses;
        `ifndef SOC
        let r <- axi_rd.response.get();
        mem_rd_resp_f_v[r.id].enq(r.data);
        `else
        let r = res_fifo.first();
        res_fifo.deq();
        mem_rd_resp_f_v[tpl_2(r)].enq(tpl_1(r));
        `endif
        
    endrule

    //read/AMO pipe

    // first, acquire all incoming read requests and sort them into the queue
    Ehr#(TAdd#(1, NUM_CPU), MIMO::LUInt#(NUM_CPU)) rd_req_in_count <- mkEhr(0); // state how many inputs were collected

    Vector#(NUM_CPU, Wire#(Rd_req)) incoming_inst <- replicateM(mkDWire(?));
    rule reset_count_and_collapse_buffer;
        rd_req_in_count[valueOf(NUM_CPU)] <= 0;
        load_queue.enq(rd_req_in_count[valueOf(NUM_CPU)], Vector::readVReg(incoming_inst));
    endrule

    // implement reading
    rule compute_input;
        let in = load_queue.first()[0];
        load_queue.deq(1);
        
            `ifndef SOC
            axi_rd.request.put(AXI4_Read_Rq {
                id: in.cpu_id,
                addr: in.addr,
                burst_length: 0,
                burst_size: B4,
                burst_type: INCR,
                lock: NORMAL,
                cache: NORMAL_NON_CACHEABLE_NON_BUFFERABLE,
                prot: UNPRIV_SECURE_DATA,
                qos: 0,
                region: 0,
                user: 0
            });
            `else
            req_fifo.enq(tuple2(unpack(in.addr), in.cpu_id));
            `endif
    endrule

    for(Integer i = 0; i < valueOf(NUM_CPU); i=i+1) begin
        rule commit_request if (load_queue.enqReadyN(rd_req_in_count[i]+1));
            let in = mem_rd_req_f_v[i].first();
            mem_rd_req_f_v[i].deq();
            rd_req_in_count[i] <= rd_req_in_count[i]+1;
            incoming_inst[rd_req_in_count[i]] <= Rd_req {addr: in, cpu_id: fromInteger(i)};
        endrule
    end

    // read request interface
    // provide incoming data in order for reset_count_and_collapse_buffer rule
    Vector#(NUM_CPU, Server#(Bit#(XLEN), Bit#(ifuwidth))) reads_loc = ?;
    for(Integer i = 0; i < valueOf(NUM_CPU); i=i+1) begin
        reads_loc[i] = (interface Server;
            interface Put request;
                method Action put(Bit#(XLEN) in);
                    mem_rd_req_f_v[i].enq(in);
                endmethod
            endinterface
            interface Get response = toGet(mem_rd_resp_f_v[i]);
        endinterface);
    end

    interface reads = reads_loc;

    // axi to data memory
    `ifndef SOC
        interface axi_r = axi_rd.fab();
    `else
        interface Client imem_r;
            interface Get request = toGet(req_fifo);
            interface Put response = toPut(res_fifo);
        endinterface
    `endif

endmodule

endpackage