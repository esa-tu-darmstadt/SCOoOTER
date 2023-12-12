package SocTop;

    import SCOOOTER_riscv::*;
    import Interfaces :: *;
    import Types :: *;
    import BlueAXI :: *;
    import Connectable :: *;
    import GetPut :: *;
    import ClientServer::*;
    import SRAMFile::*;
    import FIFO::*;
    import SpecialFIFOs::*;
    import DPSRAMFile::*;
    import Vector::*;
    import TestFunctions::*;
    import Dave::*;
    import IN22FDX_S1PV_NPVG_W16384B032M16C128::*;
    import BRAM::*;
    import DMemWrapper::*;

    // RVController emulation defines
    typedef 'h11000010 RV_CONTROLLER_RETURN_ADDRESS;
    typedef 'h11004000 RV_CONTROLLER_INTERRUPT_ADDRESS;
    typedef 'h11008000 RV_CONTROLLER_PRINT_ADDRESS;
    typedef 'h1100c000 RV_CONTROLLER_IO_OUT_ADDRESS;
    typedef 'h1100c004 RV_CONTROLLER_IO_IN_ADDRESS;

    interface SocIfc;
        (* always_ready, always_enabled *)
        method Bit#(8) io_out();
        (* always_ready, always_enabled *)
        method Action io_in(Bit#(8) in);
    endinterface

    module mkSocTop(SocIfc) provisos (
        Mul#(XLEN, IFUINST, ifuwidth),
        Div#(ifuwidth, 8, ifu_bytes_t),
        Div#(BRAMSIZE, ifu_bytes_t, imem_words_t),

        Div#(BRAMSIZE, 2, imem_ext_words_t),
        Log#(imem_ext_words_t, bram_word_ctr_t),

        Div#(BRAMSIZE, 4, bram_word_num_t),
        Log#(bram_word_num_t, ibram_addr_t),

        Log#(NUM_CPU, cpu_idx_t),
        Add#(cpu_idx_t, 1, cpu_and_amo_idx_t)
    );

        let dut <- mkDave();

        // IO
        Vector#(2, Reg#(Bit#(8))) io_out_v <- replicateM(mkRegU());
        Vector#(2, Reg#(Bit#(8))) io_in_v <- replicateM(mkRegU());

        rule propagate_io;
            io_out_v[1] <= io_out_v[0];
            io_in_v[1] <= io_in_v[0];
        endrule

        let imem <- mkIN22FDX_S1PV_NPVG_W16384B032M16C128_BitEn();

        FIFO#(Bit#(0)) read_pend_imem <- mkPipelineFIFO();

        // handle read requests
        rule ifuread;
    		let r <- dut.imem_r.request.get();
            UInt#(ibram_addr_t) addr = truncate(unpack((pack(tpl_1(r))>>2)/fromInteger(valueOf(IFUINST))));
            // the address must be converted to a word-address
            let req = BRAMRequestBE {
                address  : addr,
                datain : 0,
                writeen    : 0,
                responseOnWrite: False
            };
            imem.portA.request.put(req);
            read_pend_imem.enq(0);
  	    endrule

        // pass SRAM response to DUT via AXI
        rule ifuresp;
            read_pend_imem.deq();
            let r <- imem.portA.response.get();
            dut.imem_r.response.put(tuple2(extend(r), 0));
        endrule

        // DATA MEMORY
        AXI4_Slave_Wr#(XLEN, XLEN, cpu_and_amo_idx_t, 0) dram_axi_w <- mkAXI4_Slave_Wr(1, 1, 1);
        AXI4_Slave_Rd#(XLEN, XLEN, cpu_and_amo_idx_t, 0) dram_axi_r <- mkAXI4_Slave_Rd(1, 1);
        mkConnection(dram_axi_w.fab ,dut.dmem_axi_w);
        mkConnection(dram_axi_r.fab ,dut.dmem_axi_r);

        // create BRAM
        BRAM_Configure cfg_d = defaultValue;
        cfg_d.allowWriteResponseBypass = False;
        cfg_d.memorySize = valueOf(bram_word_num_t);
        cfg_d.latency = 1;

        let dmem <- mkDMemWrapper();

        // Buffer for write address prior to data arrival
        FIFO#(AXI4_Write_Rq_Addr#(XLEN, cpu_and_amo_idx_t, 0)) w_request <- mkPipelineFIFO();

        FIFO#(Bit#(cpu_and_amo_idx_t)) w_id <- mkPipelineFIFO();
    
        // get address requests and store them
  	    rule handleWriteRequest;
        	let r <- dram_axi_w.request_addr.get();
            w_id.enq(r.id);
        	w_request.enq(r);
    	endrule

        // handle data requests
    	rule returnWriteValue;
        	let r <- dram_axi_w.request_data.get();
            let addr = w_request.first().addr; w_request.deq();
            let data = r.data;
            
            // request we will send to BRAM
            let request = BRAMRequestBE{
                            writeen: 0,
                            responseOnWrite: True,
                            address: 0,
                            datain: 0
                        };

            // update RVController and dummy-read BRAM or access BRAM if in data range
            case (addr)
                fromInteger(valueOf(RV_CONTROLLER_INTERRUPT_ADDRESS)):
                    begin
                        // update status
                        $finish();
                    end
                fromInteger(valueOf(RV_CONTROLLER_RETURN_ADDRESS)):
                    begin
                        // update status
                        $display("return: ", data);
                    end
                fromInteger(valueOf(RV_CONTROLLER_IO_OUT_ADDRESS)):
                    begin
                        io_out_v[0] <= truncate(data);
                    end
                default:
                    if(addr < fromInteger(2*valueOf(BRAMSIZE)) && addr >= fromInteger(valueOf(BRAMSIZE)))
                    begin
                        request.writeen = r.strb;
                        request.address = ((addr-fromInteger(valueOf(BRAMSIZE)))>>2);
                        request.datain = data;
                    end
            endcase
            // send request
            dmem.portA.request.put(BRAMRequestBE {writeen : r.strb, address: unpack(truncate(addr)), datain : data});
            w_id.deq();
            dram_axi_w.response.put(AXI4_Write_Rs {id: w_id.first(), resp: OKAY, user:0});
    	endrule

        FIFO#(Bit#(cpu_and_amo_idx_t)) r_id <- mkPipelineFIFO();

        FIFO#(Bool) io_rd <- mkPipelineFIFO();

        // read data
        rule dataread;
    		let r <- dram_axi_r.request.get();
            r_id.enq(r.id);

            if(r.addr == fromInteger(valueOf(RV_CONTROLLER_IO_IN_ADDRESS))) io_rd.enq(True);
            else io_rd.enq(False);

            // if in DRAM range, send sensible request
            if(r.addr < fromInteger(2*valueOf(BRAMSIZE)) && r.addr >= fromInteger(valueOf(BRAMSIZE)))
                dmem.portB.request.put(BRAMRequestBE{
                    writeen: 0,
                    responseOnWrite: True,
                    address: unpack(truncate((r.addr)>>2)),
                    datain: 0
                });
            // if out of range, send dummy
            else dmem.portB.request.put(BRAMRequestBE{ writeen: 0, responseOnWrite: True, address: 0, datain: 0});
  	    endrule

        // forward reply via AXI
        rule dataresp;
            io_rd.deq();
            r_id.deq();
            let r <- dmem.portB.response.get();
            dram_axi_r.response.put(AXI4_Read_Rs {data: io_rd.first() ? extend(io_in_v[1]) : r, id: r_id.first(), resp: OKAY, last: True, user: 0});
        endrule

        rule no_int;
            dut.sw_int(replicate(replicate(False)));
            dut.timer_int(replicate(replicate(False)));
            dut.ext_int(replicate(replicate(False)));
        endrule

        method Bit#(8) io_out() = io_out_v[1];
        method Action io_in(Bit#(8) in) = io_in_v[0]._write(in);

    endmodule

endpackage