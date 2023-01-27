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

module mkMemoryArbiter(MemoryArbiterIFC);

    //AXI modules
    AXI4_Master_Rd#(XLEN, XLEN, 1, 0) axi_rd <- mkAXI4_Master_Rd(0, 0, False);
    AXI4_Master_Wr#(XLEN, XLEN, 1, 0) axi_wr <- mkAXI4_Master_Wr(0, 0, 0, False);

    PulseWire amo_notify_wire <- mkPulseWire();
    Reg#(Bool) amo_in_progress <- mkReg(False);

    FIFO#(Tuple3#(Bit#(XLEN), Bit#(XLEN), AmoType)) amo_description <- mkPipelineFIFO();

    Reg#(Maybe#(Bit#(XLEN))) link_lrsc <- mkReg(tagged Invalid);

    Wire#(Bit#(XLEN)) result_read <- mkWire();
    Wire#(Bit#(XLEN)) result_amo <- mkWire();
    rule distribute_read_responses;
        let r <- axi_rd.response.get();
        if (r.id == 0) result_read <= r.data;
        else           result_amo  <= r.data;
    endrule

    PulseWire result_write <- mkPulseWire();
    PulseWire write_amo <- mkPulseWire();
    rule distribute_write_responses;
        let r <- axi_wr.response.get();
        if (r.id == 0) result_write.send();
        else           write_amo.send();
    endrule

    FIFO#(Bit#(XLEN)) reg_amo <- mkPipelineFIFO();

    rule amo_transform_data if (amo_in_progress && !write_amo);
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

        reg_amo.enq(read_data);

        if (tpl_3(amo_description.first()) != LR) begin
            axi_wr.request_addr.put(AXI4_Write_Rq_Addr {
                        id: 1,
                        addr: tpl_1(amo_description.first()),
                        burst_length: 0,
                        burst_size: B1,
                        burst_type: defaultValue,
                        lock: defaultValue,
                        cache: defaultValue,
                        prot: defaultValue,
                        qos: 0,
                        region: 0,
                        user: 0
                    });
                    axi_wr.request_data.put(AXI4_Write_Rq_Data {
                        data: write_data,
                        strb: 'hf,
                        last: True,
                        user: 0
                    });
        end else begin
            amo_in_progress <= False;
        end
    endrule

    rule resume_normal_operation_after_amo if (amo_in_progress && write_amo);
        amo_in_progress <= False;
    endrule

    // AMO operations
    interface Server amo;
        interface Put request;
            method Action put(Tuple3#(Bit#(XLEN), Bit#(XLEN), AmoType) desc) if (!amo_in_progress);
                amo_notify_wire.send();

                if(tpl_3(desc) == LR) link_lrsc <= tagged Valid tpl_1(desc);
                
                if(tpl_3(desc) != SC) begin
                    amo_description.enq(desc);

                    axi_rd.request.put(AXI4_Read_Rq {
                        id: 1,
                        addr: tpl_1(desc),
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

                    amo_in_progress <= True;
                end else begin

                    // calculate failure
                    if(link_lrsc matches tagged Valid .v &&& v == tpl_1(desc)) begin
                        reg_amo.enq(0);
                        // write
                        axi_wr.request_addr.put(AXI4_Write_Rq_Addr {
                            id: 1,
                            addr: tpl_1(desc),
                            burst_length: 0,
                            burst_size: B1,
                            burst_type: defaultValue,
                            lock: defaultValue,
                            cache: defaultValue,
                            prot: defaultValue,
                            qos: 0,
                            region: 0,
                            user: 0
                        });
                        axi_wr.request_data.put(AXI4_Write_Rq_Data {
                            data: tpl_2(desc),
                            strb: 'hf,
                            last: True,
                            user: 0
                        });

                        amo_in_progress <= True;
                    end else begin
                        reg_amo.enq(1);
                        amo_in_progress <= False;
                    end

                    // invalidate
                    link_lrsc <= tagged Invalid;

                    
                end
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Bit#(XLEN)) get();
                reg_amo.deq();
                return reg_amo.first();
            endmethod
        endinterface
    endinterface

    // normal reads/writes
    interface Server write;
        interface Put request;
            method Action put(MemWr write) if (!amo_notify_wire && !amo_in_progress);

                axi_wr.request_addr.put(AXI4_Write_Rq_Addr {
                    id: 0,
                    addr: pack(write.mem_addr),
                    burst_length: 0,
                    burst_size: B1,
                    burst_type: defaultValue,
                    lock: defaultValue,
                    cache: defaultValue,
                    prot: defaultValue,
                    qos: 0,
                    region: 0,
                    user: 0
                });
                axi_wr.request_data.put(AXI4_Write_Rq_Data {
                    data: write.data,
                    strb: write.store_mask,
                    last: True,
                    user: 0
                });

                if(link_lrsc matches tagged Valid .v &&& v == pack(write.mem_addr))
                    link_lrsc <= tagged Invalid;
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(void) get() if (result_write);
                return ?;
            endmethod
        endinterface
    endinterface

    interface Server read;
        interface Put request;
            method Action put(Bit#(XLEN) req) if (!amo_notify_wire && !amo_in_progress);
                axi_rd.request.put(AXI4_Read_Rq {
                    id: 0,
                    addr: req,
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
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Bit#(XLEN)) get();
                return result_read;
            endmethod
        endinterface
    endinterface

    // axi to data memory
    interface axi_r = axi_rd.fab();
    interface axi_w  = axi_wr.fab();

endmodule

endpackage