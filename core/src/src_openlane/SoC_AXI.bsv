package SoC_AXI;
    import Assert::*;
    
    import GetPut::*;
    import ClientServer::*;
    import BlueAXI :: *;
    import Memory::*;
    import DefaultValue::*;
    import SoC_Config::*;
    import FIFO::*;
    import FIFOF::*;
    import SpecialFIFOs::*;
    import Clocks::*;
    import BRAM::*;
    import Connectable::*;
    import Vector::*;
    // defines whether SRAM macros (hardware) or BRAM models (simulation) are used
    `ifdef BLUESRAM
        import BUtils::*;
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


    /*
    
    AXI wrapper for the SoC design. Adapts internal memory interface to external AXI.

    */

    interface SoCIntf;
        // AXI slave interface
        (* prefix="s_axi" *) interface AXI4_Lite_Slave_Rd_Fab#(32, 32) s_axi_bram_rd;
        (* prefix="s_axi" *) interface AXI4_Lite_Slave_Wr_Fab#(32, 32) s_axi_bram_wr;

        // GPIO input and output
        (* always_ready, always_enabled *)
        method Action gpio_in(Bit#(32) d);
        (* always_ready, always_enabled *)
        method Bit#(32) gpio_out;

        // IRQ from SCOoOTER to Caravel
        (*always_ready, always_enabled*)
        method Bool irq_vex();
    endinterface
    
    (* synthesize *)
    module mkSoC(SoCIntf);

        // S-AXI BRAM - Slave towards Caravel
        AXI4_Lite_Slave_Wr#(32, 32) s_axi_bram_wr_inst <- mkAXI4_Lite_Slave_Wr(32);
        AXI4_Lite_Slave_Rd#(32, 32) s_axi_bram_rd_inst <- mkAXI4_Lite_Slave_Rd(32);

        // instantiate generic SoC
        // This module just adapts the SoC bus to AXI
        let dut <- mkSoC_Base();

        // FIFO to store if last request was a read or write access
        FIFO#(Bool) r_nw <- mkPipelineFIFO();

        // Write request forwarding
        rule bus_rq_w;
            let r <- s_axi_bram_wr_inst.request.get();
            dut.ext_bus.request.put(MemoryRequest {write: True,
                                                  byteen: r.strb,
                                                  address: r.addr,
                                                  data: r.data});

            r_nw.enq(False);
        endrule

        // Write response forwarding
        rule bus_rs_w if (!r_nw.first());
            r_nw.deq();
            let r <- dut.ext_bus.response.get();
            s_axi_bram_wr_inst.response.put(AXI4_Lite_Write_Rs_Pkg {resp: OKAY});
        endrule

        // read request forwarding
        rule bus_rq_r;
            let r <- s_axi_bram_rd_inst.request.get();
            dut.ext_bus.request.put(MemoryRequest {write: False,
                                                  byteen: 0,
                                                  address: r.addr,
                                                  data: 0});

            r_nw.enq(True);
        endrule

        // read response forwarding
        rule bus_rs_r if (r_nw.first());
            r_nw.deq();
            let r <- dut.ext_bus.response.get();
            s_axi_bram_rd_inst.response.put(AXI4_Lite_Read_Rs_Pkg {data: r, resp: OKAY});
        endrule

        // AXI signals
        interface AXI4_Lite_Slave_Rd_Fab s_axi_bram_rd = s_axi_bram_rd_inst.fab;
        interface AXI4_Lite_Slave_Wr_Fab s_axi_bram_wr = s_axi_bram_wr_inst.fab;

        // GPIOs and interrupt pins
        interface gpio_in  = dut.gpio_in;
        interface gpio_out = dut.gpio_out;
        interface irq_vex  = dut.irq_vex;

    endmodule

endpackage







