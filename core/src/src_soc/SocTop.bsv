package SocTop;

    import SCOOOTER_riscv::*;
    import Interfaces :: *;
    import Types :: *;
    import BlueAXI :: *;
    import Connectable :: *;
    import GetPut :: *;
    import ClientServer::*;
    import SRAMFile::*;
    import SyncSRAM::*;
    import FIFO::*;
    import SpecialFIFOs::*;
    import DPSRAMFile::*;
    import Vector::*;
    import TestFunctions::*;

    // RVController emulation defines
    typedef 'h11000010 RV_CONTROLLER_RETURN_ADDRESS;
    typedef 'h11004000 RV_CONTROLLER_INTERRUPT_ADDRESS;
    typedef 'h11008000 RV_CONTROLLER_PRINT_ADDRESS;

    module mkSocTop(Empty) provisos (
        Mul#(XLEN, IFUINST, ifuwidth),
        Div#(ifuwidth, 8, ifu_bytes_t),
        Div#(BRAMSIZE, ifu_bytes_t, imem_words_t),

        Div#(BRAMSIZE, 4, bram_word_num_t)
    );

        let dut <- mkSCOOOTER_riscv();

        // IMEM
        AXI4_Slave_Rd#(XLEN, ifuwidth, 0, 0) iram_axi <- mkAXI4_Slave_Rd(0, 0);
        mkConnection(dut.imem_axi, iram_axi.fab);

        SyncSRAMS#(1, 32, ifuwidth) sram <- mkSRAMFile("../../testPrograms/embench/"+"edn"+"/32bit/bsv_hex/"+"edn"+"_"+ select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", valueOf(imem_words_t));

        FIFO#(Bit#(0)) read_pend_imem <- mkPipelineFIFO();

        // handle read requests
        rule ifuread;
    		let r <- iram_axi.request.get();
            // the address must be converted to a word-address
            let req = SyncSRAMrequest {
                addr  : (r.addr>>2)/fromInteger(valueOf(IFUINST)),
                wdata : ?,
                we    : 0,
                ena   : 1
            };
            sram.request.put(req);
            read_pend_imem.enq(0);
  	    endrule

        // pass SRAM response to DUT via AXI
        rule ifuresp;
            read_pend_imem.deq();
            let r <- sram.response.get();
            iram_axi.response.put(AXI4_Read_Rs {data: r, id: 0, resp: OKAY, last: True, user: 0});
        endrule

        // DMEM
        AXI4_Slave_Wr#(XLEN, XLEN, 1, 0) dram_axi_w <- mkAXI4_Slave_Wr(0, 0, 0);
        AXI4_Slave_Rd#(XLEN, XLEN, 1, 0) dram_axi_r <- mkAXI4_Slave_Rd(0, 0);
        mkConnection(dram_axi_w.fab ,dut.dmem_axi_w);
        mkConnection(dram_axi_r.fab ,dut.dmem_axi_r);

        // we create four BRAMs
        // one per byte to achieve a BE signal
        Vector#(4, Tuple2#(
            SyncSRAMS#(1, 32, 8), 
            SyncSRAMS#(1, 32, 8)))
            dsram = ?;
        for(Integer i = 0; i < 4; i = i + 1)
            dsram[i] <- mkDPSRAMFile(
                "../../testPrograms/embench/"+"edn"+"/32bit/bsv_hex/"+"edn"+"-data_32_"+ select_fitting_sram_byte(i) + ".bsv"
                , valueOf(bram_word_num_t));

        // reading
        FIFO#(Bit#(XLEN)) r_id <- mkPipelineFIFO(); // store request ID

        rule data_read;
    		let r <- dram_axi_r.request.get();
            r_id.enq(extend(r.id));

            // calculate addr, if it is not in DRAM range, read from 0
            // TODO: also add tests for external IO (or disallow speculative reads into that space)
            let effective_addr = (r.addr < fromInteger(2*valueOf(BRAMSIZE)) && r.addr >= fromInteger(valueOf(BRAMSIZE))) ?
                ((r.addr-fromInteger(valueOf(BRAMSIZE)))>>2) : 0;

            for(Integer i = 0; i < 4; i=i+1) begin
                tpl_1(dsram[i]).request.put(SyncSRAMrequest {
                    addr  : ((r.addr-fromInteger(valueOf(BRAMSIZE)))>>2),
                    wdata : ?,
                    we    : 0,
                    ena   : 1
                });
            end
  	    endrule

        // forward reply via AXI
        rule data_resp_r;
            Bit#(XLEN) resp = ?;

            for(Integer i = 0; i < 4; i=i+1) begin
                resp[i*8+7:i*8] <- tpl_1(dsram[i]).response.get();
            end

            r_id.deq();
            dram_axi_r.response.put(AXI4_Read_Rs {data: resp, id: truncate(r_id.first()), resp: OKAY, last: True, user: 0});
        endrule


        // write
        // Buffer for write address prior to data arrival
        FIFO#(AXI4_Write_Rq_Addr#(XLEN, 1, 0)) w_request <- mkPipelineFIFO();
        // buffer for write request id
        FIFO#(Bit#(XLEN)) w_id <- mkPipelineFIFO();
        // pending fifo to synchronize response deq
        FIFO#(Bit#(0)) write_pend_dmem <- mkPipelineFIFO();
    
        // get address requests and store them
  	    rule handle_write_addr_request;
        	let r <- dram_axi_w.request_addr.get();
            w_id.enq(extend(r.id));
        	w_request.enq(r);
    	endrule

        // handle data requests
    	rule handle_write_data_request;
        	let r <- dram_axi_w.request_data.get();
            let data = r.data;
            let addr = w_request.first().addr; w_request.deq();

            if (addr == fromInteger(valueOf(RV_CONTROLLER_INTERRUPT_ADDRESS))) $finish();

            // add handling of other addresses here if necessary

            // clean up address handling to deal with wrong addresses
            if(addr >= fromInteger(2*valueOf(BRAMSIZE)) || addr < fromInteger(valueOf(BRAMSIZE)))
                addr = fromInteger(valueOf(BRAMSIZE));
            // dmem handling:
            for(Integer i = 0; i < 4; i=i+1) begin
                tpl_2(dsram[i]).request.put(SyncSRAMrequest {
                    addr  : ((addr-fromInteger(valueOf(BRAMSIZE)))>>2),
                    wdata : data[i*8+7:i*8],
                    we    : r.strb[i],
                    ena   : 1
                });
            end
            write_pend_dmem.enq(0);
    	endrule

        // get SRAM response and just AXI that request was successful
        rule data_write_resp;
            write_pend_dmem.deq();
            w_id.deq();
            dram_axi_w.response.put(AXI4_Write_Rs {id: truncate(w_id.first()), resp: OKAY, user:0});
            for(Integer i = 0; i < 4; i=i+1) begin
                let d <- tpl_2(dsram[i]).response.get();
            end
        endrule

        rule no_int;
            dut.sw_int(False);
            dut.timer_int(False);
            dut.ext_int(False);
        endrule


    endmodule

endpackage