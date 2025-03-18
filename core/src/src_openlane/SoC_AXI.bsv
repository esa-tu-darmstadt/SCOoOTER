package SoC_AXI;
    import Assert::*;
    
    import GetPut::*;
    import ClientServer::*;
    import BlueAXI :: *;
    //import Wishbone::*;
    import Memory::*; // wishbone memory request and response
    import DefaultValue::*;

    //From Scoooter
    import SoC_Config::*;
    import FIFO::*;
    import FIFOF::*;
    import SpecialFIFOs::*;
    import Clocks::*;
    import BRAM::*;
    import Connectable::*;
    import Vector::*;
    import SoC_Types::*;
`ifdef BLUESRAM
    import BUtils::*; // cExtend() workaround
    import EFSRAM::*;
`else
    import BRAMCore::*;
`endif
    import SPICore::*;
    import MemoryDecoder::*;
    import RegFile::*;
    import OpenRAMIfc::*;
    import WrapBRAMAsOpenRAM::*;
    import SoC_Base::*;


    interface SoCIntf;
        (* prefix="s_axi" *) interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_axi_bram_rd;
        (* prefix="s_axi" *) interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_axi_bram_wr;

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
    
    (* synthesize *)
    module mkSoC(SoCIntf);

        // S-AXI BRAM - Slave towards outside World
        AXI4_Lite_Slave_Wr#(32, 32) s_axi_bram_wr_inst <- mkAXI4_Lite_Slave_Wr(32);
        AXI4_Lite_Slave_Rd#(32, 32) s_axi_bram_rd_inst <- mkAXI4_Lite_Slave_Rd(32);

        let dut <- mkSoC_Base();

        /*
        * Buffer Wishbone
        */
        // Never buffer more than 8 outstanding response requests. We will do max 4.

        FIFO#(Bool) r_nw <- mkPipelineFIFO();

        rule bus_rq_w;
            let r <- s_axi_bram_wr_inst.request.get();
            dut.ext_bus.request.put(MemoryRequest {write: True,
                                                  byteen: r.strb,
                                                  address: r.addr,
                                                  data: r.data});

            r_nw.enq(False);
        endrule

        rule bus_rs_w if (!r_nw.first());
            r_nw.deq();
            let r <- dut.ext_bus.response.get();
            s_axi_bram_wr_inst.response.put(AXI4_Lite_Write_Rs_Pkg {resp: OKAY});
        endrule

        rule bus_rq_r;
            let r <- s_axi_bram_rd_inst.request.get();
            dut.ext_bus.request.put(MemoryRequest {write: False,
                                                  byteen: 0,
                                                  address: r.addr,
                                                  data: 0});

            r_nw.enq(True);
        endrule

        rule bus_rs_r if (r_nw.first());
            r_nw.deq();
            let r <- dut.ext_bus.response.get();
            s_axi_bram_rd_inst.response.put(AXI4_Lite_Read_Rs_Pkg {data: r, resp: OKAY});
        endrule

        interface irq = dut.irq;

        // SPI signals
        interface spi_clk_dmem = dut.spi_clk_dmem;
        interface spi_mosi_dmem = dut.spi_mosi_dmem;
        interface spi_miso_dmem = dut.spi_miso_dmem;
        interface spi_cs_dmem = dut.spi_cs_dmem;

        interface spi_clk_imem = dut.spi_clk_imem;
        interface spi_mosi_imem = dut.spi_mosi_imem;
        interface spi_miso_imem = dut.spi_miso_imem;
        interface spi_cs_imem = dut.spi_cs_imem;


        // GPIOs
        interface gpio_out = dut.gpio_out;
        interface gpio_in = dut.gpio_in;

        // Failsafes
        interface fs_dexie_disable = dut.fs_dexie_disable;
        interface fs_mgmt_disable = dut.fs_mgmt_disable;
        interface fs_boot_from_SPI = dut.fs_boot_from_SPI;

        interface AXI4_Lite_Slave_Rd_Fab s_axi_bram_rd = s_axi_bram_rd_inst.fab;
        interface AXI4_Lite_Slave_Wr_Fab s_axi_bram_wr = s_axi_bram_wr_inst.fab;

        interface fs_stall_core = dut.fs_stall_core;
        interface fs_int_core = dut.fs_int_core;
        interface irq_vex = dut.irq_vex;

    endmodule

endpackage







