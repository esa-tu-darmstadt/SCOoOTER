package SoC_Base;
    import Assert::*;
    
    import GetPut::*;
    import ClientServer::*;
    import BlueAXI :: *;
    //import Wishbone::*;
    import Memory::*; // wishbone memory request and response
    import DefaultValue::*;
    import SoC_Config::*;
    import FIFO::*;
    import FIFOF::*;
    import SpecialFIFOs::*;
    import Clocks::*;
    import BRAM::*;
    import Connectable::*;
    import Vector::*;
    import RegFile::*;
    import Config::*;

    import SoC_Mem::*;

    import SCOoOTER_wrapper::*;


    import SoC_Types::*;

    typedef enum {IMEM, DMEM, DEXIE_R, DEXIE_W, DEXIE_CTRL_R, DEXIE_CTRL_W, DUMMY} MemRouting deriving(Bits, Eq, FShow);
    typedef enum {MEM, DXCTL, DX} AccType deriving(Bits, FShow, Eq);

    interface SoCIntf_base;
        interface Server#(MemoryRequest#(32,32), Bit#(32)) ext_bus;

        (* always_ready *) method Bool irq();

        // SPI signals
        (*always_ready, always_enabled*)
        method Bit#(1) spi_clk_dmem;
        (*always_ready, always_enabled*)
        method Bit#(1) spi_mosi_dmem;
        (*always_ready, always_enabled*)
        method Action spi_miso_dmem(Bit#(1) i);
        (*always_ready, always_enabled*)
        method Bool spi_cs_dmem;

        (*always_ready, always_enabled*)
        method Bit#(1) spi_clk_imem;
        (*always_ready, always_enabled*)
        method Bit#(1) spi_mosi_imem;
        (*always_ready, always_enabled*)
        method Action spi_miso_imem(Bit#(1) i);
        (*always_ready, always_enabled*)
        method Bool spi_cs_imem;


        // GPIOs
        (*always_ready,always_enabled*)
        method Bit#(NUM_GPIO_OUT) gpio_out;
        (*always_ready,always_enabled*)
        method Action gpio_in(Bit#(NUM_GPIO_IN) in);

        // vex_irq
        (*always_ready, always_enabled*)
        method Bool irq_vex();

        // Failsafes
        (*always_ready,always_enabled*)
        method Action fs_dexie_disable(Bool in);
        (*always_ready,always_enabled*)
        method Action fs_mgmt_disable(Bool in);
        (*always_ready,always_enabled*)
        method Action fs_boot_from_SPI(Bool in);
        (*always_ready,always_enabled*)
        method Action fs_stall_core(Bool in);

        (*always_ready,always_enabled*)
        method Action fs_int_core(Bool in);
    endinterface
    
    module mkSoC_Base(SoCIntf_base) provisos (
        Div#(SIZE_IMEM, 4, bram_word_num_imem_t),
        Div#(SIZE_DMEM, 4, bram_word_num_dmem_t)
    );

        // Instantiate DExIE and Base Core
        let core <- mkSCOoOTERWrapped();

        /**
        * AXI
        **/

        // initiate memory map
        MemMapIfc imem <- mkMEMMap(False);
        BRAM1PortBE#(Bit#(32), Bit#(32), 4) ibram = imem.access;
        MemMapIfc dmem <- mkMEMMap(True);
        BRAM1PortBE#(Bit#(32), Bit#(32), 4) dbram = dmem.access;

        rule stallAndInterruptTieOff;
            core.interrupts(False, dmem.irq_scoooter_timer(), False);
        endrule

/*
        * External access
        */
        // Define local Wishbone local addresses (MSBs already cut away)
        function Bool isImemAddrRange(Bit#(26) addr);
            return addr<fromInteger(valueOf(SIZE_IMEM));
        endfunction

        function Bool isDmemAddrRange(Bit#(26) addr);
            return addr<fromInteger(valueOf(SIZE_DMEM));
        endfunction

        /*
        * Buffer external access
        */
        FIFO#(MemoryRequest#(32,32)) requests <- mkPipelineFIFO();
        FIFO#(Bit#(32)) responses <- mkPipelineFIFO();

        FIFO#(MemRouting) inflight_rq <- mkSizedFIFO(1);

        // Return WB response
        function Action retireWbRequest(Bit#(32) data, Bool send);
            action
                if (send) begin
                    responses.enq(data);
                end
            endaction
        endfunction

        /*
        * IMEM Wishbone Access
        */
        FIFO#(Bool) inflightImemReadReq <- mkSizedFIFO(1);

        function Action toImem(MemoryRequest#(32, 32) r, Bit#(26) addr_loc);
            action
                // Filter local imem addresses
                if (!isImemAddrRange(addr_loc)) begin
                    // Send empty WB response, and deq request fifo
                    inflight_rq.enq(DUMMY);
                end else begin
                    // Forward to imem
                    ibram.portA.request.put(BRAMRequestBE{writeen: signExtend(pack(r.write)), responseOnWrite: True, address: extend((addr_loc>>2)), datain: r.data});
                    inflight_rq.enq(IMEM);
                    inflightImemReadReq.enq(False);
                end
            endaction
        endfunction

        rule imemWbResponse if (inflight_rq.first == IMEM && !inflightImemReadReq.first());
            inflight_rq.deq();
            let resp_data <- ibram.portA.response.get();
            retireWbRequest(resp_data, True);
            inflightImemReadReq.deq();
        endrule


        /*
        * DMEM Wishbone Access
        */

        function Action toDmem(MemoryRequest#(32, 32) r, Bit#(26) addr_loc);
            action
                // Filter local addresses
                if (!isDmemAddrRange(addr_loc)) begin
                    // Send empty WB response, and deq request fifo
                    inflight_rq.enq(DUMMY);
                end else begin
                    // Forward to imem
                    dbram.portA.request.put(BRAMRequestBE{writeen: 'hF, responseOnWrite: False, address: (extend(addr_loc)>>2), datain: r.data});
                    inflight_rq.enq(DMEM);
                end
            endaction
        endfunction

        rule dmemReadResponse if (inflight_rq.first() == DMEM);
            inflight_rq.deq();
            let resp_data <- dbram.portA.response.get();
            retireWbRequest(resp_data, True);
        endrule

        rule dmemDummyResponse if (inflight_rq.first() == DUMMY);
            inflight_rq.deq();
            retireWbRequest(0, True);
        endrule

        /*
        * Wishbone Router
        * - Forward wishbone requests to the appropriate memory.
        * - Handle only one request in flight at a time to keep order of responses simple.
        * - Use 2 bits [27:26] to select target.
        */
        Reg#(Bool) rst_active <- mkReg(True);

        rule wishboneRouter;
            let r = requests.first();
            requests.deq();
            Bit#(2) msbs = r.address[27:26];
            Bit#(26) addr_loc = r.address[25:0];

            // writes into any DExIE region trigger core to run
            if (r.address >= 32'h_30_00_00_00 + (wb_offset_dex_mem << 26)) rst_active <= False;

            case (msbs)
                fromInteger(valueOf(WB_OFFSET_IMEM)):        toImem(r, addr_loc);
                fromInteger(valueOf(WB_OFFSET_DMEM)):        toDmem(r, addr_loc);
            endcase
        endrule

        /*
        * Scoooter memory access
        */
        // imem read
        rule ifuread if (!rst_active);
            let r <- core.imem_r.request.get();
            
            let addr = r;
            let idx = (pack(addr)>>2);
            inflightImemReadReq.enq(True);
            ibram.portA.request.put(BRAMRequestBE{
                writeen: 0,
                responseOnWrite: True,
                address: idx,
                datain: ?
            });
          endrule

        // response
        rule ifuresp;
            inflightImemReadReq.deq();
            let r <- ibram.portA.response.get();
            core.imem_r.response.put(r);
        endrule

        // tag whether we excpect a response from dexie or memory next
        FIFO#(AccType) next_rd_mem_not_dexie <- mkPipelineFIFO();
        FIFO#(AccType) next_wr_mem_not_dexie <- mkPipelineFIFO();

        // dmem read
        rule dfuread;
            let r <- core.dmem_r.request.get();
            let addr = r;
            let idx = (addr-fromInteger(valueOf(BASE_DMEM)))>>2; // TODO: configure by addr map
            begin
                //$display("SCOOOOOTER read req");
                dbram.portA.request.put(BRAMRequestBE{
                    writeen: 0,
                    responseOnWrite: True,
                    address: pack(idx), //subtract the imem size offset, shift by 2 bit for word addressing
                    datain: ?
                });
                next_rd_mem_not_dexie.enq(MEM);
            end
        endrule

        // response
        rule dfuresp if (next_rd_mem_not_dexie.first() == MEM);
            $display("rdval dmem");
            next_rd_mem_not_dexie.deq();
            let r <- dbram.portA.response.get();
            core.dmem_r.response.put(r);
        endrule

        // dmem write
        (*descending_urgency="wishboneRouter, dfuwrite, ifuread"*)
        rule dfuwrite;
            let r <- core.dmem_w.request.get();
            let addr = tpl_1(r);
            let data = tpl_2(r);
            let strb = tpl_3(r);
            let idx = (addr-fromInteger(valueOf(BASE_DMEM)))>>2;
            begin
                $display("dmem wr");
                dbram.portA.request.put(BRAMRequestBE{
                    writeen: strb,
                    responseOnWrite: True,
                    address: pack(idx),
                    datain: data
                });
                next_wr_mem_not_dexie.enq(MEM);
            end
        endrule

        // response
        rule dfuwresp if (next_wr_mem_not_dexie.first() == MEM);
            next_wr_mem_not_dexie.deq();
            let r <- dbram.portA.response.get();
            core.dmem_w.response.put(0);
        endrule

        interface Server ext_bus;
            interface Put request = toPut(requests);
            interface Get response = toGet(responses);
        endinterface

    endmodule

endpackage
