package SoC_WB;
    import Assert::*;
    
    import GetPut::*;
    import ClientServer::*;
    import BlueAXI :: *;
    import OurWishbone::*;
    import Memory::*; // wishbone memory request and response
    import DefaultValue::*;

    //From Scoooter
    import Dave::*;
    import SoC_Config::*;
    import Types::*;
    import FIFO::*;
    import FIFOF::*;
    import SpecialFIFOs::*;
    import Clocks::*;
    import BRAM::*;
    import Interfaces::*;
    import Connectable::*;
    import Vector::*;
    import Inst_Types::*;
    import SPICore::*;
    import MemoryDecoder::*;
    import RegFile::*;
    import OpenRAMIfc::*;
    import WrapBRAMAsOpenRAM::*;
    import SoC_Base::*;
    import SoC_Types::*;


    interface CaravelInterface;
        interface WishboneSlave_IFC#(32, 32) wbs;

        // IOs strictly adhere to the naming in Caravel
        (*always_ready,always_enabled*)
        method Bit#(38) io_out;
        (*always_ready,always_enabled*)
        method Action io(Bit#(38) in);
        (*always_ready,always_enabled*)
        method Bit#(38) io_oeb;
        
        // ILA strictly adhere to the naming in Caravel
        (*always_ready,always_enabled*)
        method Action la_data(Bit#(128) in);
        (*always_ready,always_enabled*)
        method Bit#(128) la_data_out;
        (*always_ready,always_enabled, prefix=""*)
        method Action la_oenb(Bit#(128) la_oenb);

        (*always_ready,always_enabled*)
        interface Bit#(1) irq_0;
        (*always_ready,always_enabled*)
        interface Bit#(1) irq_1;
    endinterface


    interface SoCIntf;

        // Wishbone Slave
        interface WishboneSlave_IFC#(32, 32) wb_slave;

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

        (* always_ready *) method Bool irq();

        (*always_ready, always_enabled*)
        method Bool irq_vex();

        /////// ILA-connected signals ////////
        
        // Failsafe inputs
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
    
    module mkSoC(SoCIntf);
        // Wishbone Slave to the outside world
        WishboneSlaveXactor_IFC#(32, 32)  wb_slave_inst  <- mkWishboneSlaveXactor(8);

        let dut <- mkSoC_Base();

        /*
        * Buffer Wishbone
        */
        // Never buffer more than 8 outstanding response requests. We will do max 4.
        rule bus_rq;
            let r <- wb_slave_inst.client.request.get();
            //feature_log($format("got request addr %h", r.address), L_Wrapper);
            dut.ext_bus.request.put(r);
        endrule

        rule bus_rs;
            let r <- dut.ext_bus.response.get();
            wb_slave_inst.client.response.put(MemoryResponse {data: r});
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

        interface WishboneSlave_IFC wb_slave = wb_slave_inst.wishbone;

        interface fs_stall_core = dut.fs_stall_core;
        interface fs_int_core = dut.fs_int_core;
        interface irq_vex = dut.irq_vex;

    endmodule

    (* synthesize, clock_prefix = "CLK" *)
    module mkScoooterCaravel(CaravelInterface);
        let sys <- mkSoC();
        // Configure IO output enables
        //method Bit#(38) io_oeb = 38'b_00_0000000000_1111111111_00_111111_00000000;
        // oeb is output = 0
        method Bit#(38) io_oeb = 38'b_11_1111111111_0000000000_11_000000_11111111;

        // IOs strictly adhere to the naming in Caravel
        method Bit#(38) io_out = {
            2'b_00,                    // 37, 36 Forbidden!
            10'b_0000000000,        // 35...26 GPIO inputs 10x
            sys.gpio_out,            // 25...16 GPIO outputs 10x
            2'b_00,                    // 15, 14 SPI inputs
            pack(sys.spi_cs_imem),     // 13
            sys.spi_mosi_imem,        // 12
            sys.spi_clk_imem,       // 11
            pack(sys.spi_cs_dmem),    // 10
            sys.spi_mosi_dmem,      //  9
            sys.spi_clk_dmem,       //  8
            8'b_00000000            //  7...0 Forbidden
        };

        // method Bit#(38) io_in = our_io_in;
        method Action io(Bit#(38) in);
            action
                // 36,37 forbidden
                sys.gpio_in(in[35:26]);
                // 16..25 forbidden
                sys.spi_miso_imem(in[15]);
                sys.spi_miso_dmem(in[14]);
                // 8..13 SPI out
                // 0..7 forbidden
            endaction
        endmethod
        

        ///////// LOGIC ANALYZER ////////
        // Dexie return code x5 (out)
        // Current_State x10 (out)
        // Current_Fsm x10 (out)
        // next_PC x30 (out)
        // current_PC x30 (out)
        // Instruction x32 (out)
        // GAP
        // 5 fs_dexie_disable_in (in)
        // 4 fs_mgmt_disable_in (in)
        // 3 fs_boot_from_SPI_in (in)
        // 2 fs_stall_core_in (in)
        // 1 fs_int_core_in (in)
        // 0 RST_N (in) : Mapped externally
        

        method Bit#(128) la_data_out = {
            0
        };

        // LA Output Enable
        //method Bit#(128) la_oenb =  128'b_11111_1111111111_1111111111_111111111111111111111111111111_111111111111111111111111111111_11111111111111111111111111111111_1000000000_0;
        method Action la_oenb(Bit#(128) oen) = noAction;
        
        method Action la_data(Bit#(128) in);
            action
                // 127..11 are outputs
                // inputs 9...6 unused
                sys.fs_dexie_disable(unpack(in[5]));                // 5
                sys.fs_mgmt_disable(unpack(in[4]));                    // 4
                sys.fs_boot_from_SPI(unpack(in[3]));                 // 3
                sys.fs_stall_core(unpack(in[2]));                    // 2
                sys.fs_int_core(unpack(in[1]));                        // 1
                // sys.RST_N(in[0]);                                // 0 Wired in Caravel Wrapper from mngmnt to reset
            endaction
        endmethod

        interface irq_0 = pack(sys.irq);
        interface irq_1 = pack(sys.irq_vex);
        // irq[2] is not assigned

        interface WishboneSlave_IFC wbs = sys.wb_slave;
    endmodule
endpackage
