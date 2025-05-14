package SoC_WB;
    import Assert::*;
    
    import GetPut::*;
    import ClientServer::*;
    import BlueAXI :: *;
    import OurWishbone::*;
    import Memory::*;
    import DefaultValue::*;

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
    import MemoryDecoder::*;
    import RegFile::*;
    import OpenRAMIfc::*;
    import WrapBRAMAsOpenRAM::*;
    import SoC_Base::*;

    /*
    
    This package contains a Wishbone wrapper and a Caravel wrapper for the base SoC design.
    
    */

    // Caravel interface
    // Defined to adhere to the Caravel specification
    interface CaravelInterface;
        // Wishbone bus from Caravel
        interface WishboneSlave_IFC#(32, 32) wbs;

        // IOs
        (*always_ready,always_enabled*)
        method Bit#(38) io_out;
        (*always_ready,always_enabled*)
        method Action io(Bit#(38) in);
        (*always_ready,always_enabled*)
        method Bit#(38) io_oeb;
        
        // ILA
        (*always_ready,always_enabled*)
        method Action la_data(Bit#(128) in);
        (*always_ready,always_enabled*)
        method Bit#(128) la_data_out;
        (*always_ready,always_enabled, prefix=""*)
        method Action la_oenb(Bit#(128) la_oenb);

        // IRQ from our design to Caravel
        (*always_ready,always_enabled*)
        interface Bit#(1) irq_1;
    endinterface


    // interface of our SoC module
    // Will be further wrapped for Caravel
    interface SoCIntf;

        // Wishbone Slave
        interface WishboneSlave_IFC#(32, 32) wb_slave;

        // GPIO input and output
        (* always_ready, always_enabled *)
        method Action gpio_in(Bit#(32) d);
        (* always_ready, always_enabled *)
        method Bit#(32) gpio_out;

        // IRQ from SCOoOTER to Caravel
        (*always_ready, always_enabled*)
        method Bool irq_vex();
    endinterface
    
    module mkSoC(SoCIntf);
        // Wishbone Slave to the outside world
        WishboneSlaveXactor_IFC#(32, 32)  wb_slave_inst  <- mkWishboneSlaveXactor(8);

        // base SoC module
        let dut <- mkSoC_Base();

        /*
        * Connect Wishbone interface
        * Requests and Responses
        */

        rule bus_rq;
            let r <- wb_slave_inst.client.request.get();
            dut.ext_bus.request.put(r);
        endrule

        rule bus_rs;
            let r <- dut.ext_bus.response.get();
            wb_slave_inst.client.response.put(MemoryResponse {data: r});
        endrule

        // Failsafes
        interface WishboneSlave_IFC wb_slave = wb_slave_inst.wishbone;
        
        // GPIOs and interrupt pins
        interface gpio_in  = dut.gpio_in;
        interface gpio_out = dut.gpio_out;
        interface irq_vex  = dut.irq_vex;

    endmodule


    // Caravel wrapper module
    // adapts our signals to Caravels specifications
    (* synthesize, clock_prefix = "CLK" *)
    module mkScoooterCaravel(CaravelInterface);
        let sys <- mkSoC();
        // Configure IO output enables
        // A pin is an output, if its bit is set to 0
        // We configure half of the pins for output and half of them for input
        method Bit#(38) io_oeb = 38'b_1111111111111111111_0000000000000000000;

        // connect the input and output GPIO signals for Caravel
        method Bit#(38) io_out = extend(sys.gpio_out());
        method Action io(Bit#(38) in);
            action
                sys.gpio_in(truncate(in >> 19));
            endaction
        endmethod
        

        // The Logic Analyzer is currently unused
        // Pin 0 is connected in an external Verilog wrapper to drive the reset signal
        method Bit#(128) la_data_out = {
            0
        };
        method Action la_oenb(Bit#(128) oen) = noAction;
        method Action la_data(Bit#(128) in) = noAction;

        // Interrupt from SCOoOTER to caravel
        interface irq_1 = pack(sys.irq_vex);
        // Wishbone interface from Caravel to the instruction / data memories
        interface WishboneSlave_IFC wbs = sys.wb_slave;
    endmodule
endpackage
