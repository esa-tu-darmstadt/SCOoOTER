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


(* synthesize *)
module mkInstructionArbiter(InstArbiterIFC) provisos (
    Log#(NUM_CPU, idx_cpu_t),
    Mul#(NUM_CPU, 2, num_by_two_cpu_t),
    Mul#(XLEN, IFUINST, ifuwidth)
);

    //AXI modules
    AXI4_Master_Rd#(XLEN, ifuwidth, idx_cpu_t, 0) axi_rd <- mkAXI4_Master_Rd(0, 0, False);

    //request buffers
    Vector#(NUM_CPU, FIFO#(Bit#(ifuwidth))) mem_rd_resp_f_v <- replicateM(mkPipelineFIFO());

    //load/store queues
    MIMO#(NUM_CPU, 1, num_by_two_cpu_t, Rd_req) load_queue <- mkMIMO(defaultValue);

    Wire#(Bit#(XLEN)) result_read <- mkWire();
    rule distribute_read_responses;
        let r <- axi_rd.response.get();
        mem_rd_resp_f_v[r.id].enq(r.data);
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
    endrule

    // read request interface
    // provide incoming data in order for reset_count_and_collapse_buffer rule
    Vector#(NUM_CPU, Server#(Bit#(XLEN), Bit#(ifuwidth))) reads_loc = ?;
    for(Integer i = 0; i < valueOf(NUM_CPU); i=i+1) begin
        reads_loc[i] = (interface Server;
            interface Put request;
                method Action put(Bit#(XLEN) in) if (load_queue.enqReadyN(rd_req_in_count[i]+1));
                    rd_req_in_count[i] <= rd_req_in_count[i]+1;
                    incoming_inst[rd_req_in_count[i]] <= Rd_req {addr: in, cpu_id: fromInteger(i)};
                endmethod
            endinterface
            interface Get response = toGet(mem_rd_resp_f_v[i]);
        endinterface);
    end

    interface reads = reads_loc;

    // axi to data memory
    interface axi_r = axi_rd.fab();

endmodule

endpackage