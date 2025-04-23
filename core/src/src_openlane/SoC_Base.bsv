package SoC_Base;
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
    import RegFile::*;
    import Config::*;
    import SoC_Mem::*;
    import SCOoOTER_wrapper::*;

    /*
    
    Base Caravel design. Connects SCOoOTER with the memories and the external bus system of Caravel.
    From the external bus, Caravel can write the instruction and data memory and start the processor.

    */

    // type to tag external requests with their destination
    typedef enum {IMEM, DMEM, DUMMY} MemRouting deriving(Bits, Eq, FShow);
    // Type to tag SCOoOTER DMEM requests with read or write
    typedef enum {RD, WR} AccType deriving(Bits, FShow, Eq);

    interface SoCIntf_base;
        // external bus from Caravel
        // used to load program binaries
        interface Server#(MemoryRequest#(32,32), Bit#(32)) ext_bus;

        // GPIO input and output
        (* always_ready, always_enabled *)
        method Action gpio_in(Bit#(32) d);
        (* always_ready, always_enabled *)
        method Bit#(32) gpio_out;

        // IRQ from SCOoOTER to Caravel
        (*always_ready, always_enabled*)
        method Bool irq_vex();
    endinterface
    
    module mkSoC_Base(SoCIntf_base) provisos (
        Div#(SIZE_IMEM, 4, bram_word_num_imem_t),
        Div#(SIZE_DMEM, 4, bram_word_num_dmem_t)
    );

        // Instantiate SCOoOTER
        let core <- mkSCOoOTERWrapped();

        // Create imem and dmem memories
        // dmem also contains periphery (e.g. CLINT)
        MemMapIfc imem <- mkMEMMap(False);
        BRAM1PortBE#(Bit#(32), Bit#(32), 4) ibram = imem.access;
        MemMapIfc dmem <- mkMEMMap(True);
        BRAM1PortBE#(Bit#(32), Bit#(32), 4) dbram = dmem.access;

        // connect timer interrupt
        rule interruptTieOff;
            core.interrupts(False, dmem.irq_scoooter_timer(), False);
        endrule

        // Prior to receiving a program binary, SCOoOTER must be stalled to avoid executing
        // random noise from the memories
        Reg#(Bool) rst_active <- mkReg(True);

        // helper functions
        // helps checking that an addess (with removed MSBs) is in a certain range
        // MSBs must be removed since they are used to route memory accesses from Caravel to the correct component
        // (in our case IMEM or DMEM)
        function Bool isImemAddrRange(Bit#(26) addr);
            return addr<fromInteger(valueOf(SIZE_IMEM));
        endfunction

        function Bool isDmemAddrRange(Bit#(26) addr);
            return addr<fromInteger(valueOf(SIZE_DMEM));
        endfunction


        /**
        * External Bus
        **/
        // Currently, the external bus can only write to the system since we only load binaries.
        // Reading back the data is currently unsupportec.


        // Create FIFOs to buffer external requests
        FIFO#(MemoryRequest#(32,32)) requests <- mkPipelineFIFO();
        FIFO#(Bit#(32)) responses <- mkPipelineFIFO();

        // store which unit is handling the current request
        // can be IMEM, DMEM or DUMMY
        // DUMMY means, we respond although the request hit an empty memory map space
        // this avoids a lockup of Caravel due to never receiving a response
        FIFO#(MemRouting) inflight_rq <- mkSizedFIFO(1);

        /*
        * IMEM External Access
        */

        // function to handle requests from Caravel to the IMEM
        function Action toImem(MemoryRequest#(32, 32) r, Bit#(26) addr_loc);
            action
                // Filter local imem addresses
                if (!isImemAddrRange(addr_loc)) begin
                    // Send empty response if out of range
                    inflight_rq.enq(DUMMY);
                end else begin
                    // Forward to imem
                    ibram.portA.request.put(BRAMRequestBE{writeen: signExtend(pack(r.write)), responseOnWrite: True, address: extend((addr_loc>>2)), datain: r.data});
                    // store that we handle an IMEM request
                    inflight_rq.enq(IMEM);
                end
            endaction
        endfunction

        // respond to the external bus
        // only fires if we are handling an imem write
        rule imemResponse if (inflight_rq.first == IMEM);
            // empty FIFOs
            inflight_rq.deq();
            let resp_data <- ibram.portA.response.get();
            responses.enq(resp_data);
        endrule


        /*
        * DMEM External Access
        */

        // function to handle requests from Caravel to the DMEM
        function Action toDmem(MemoryRequest#(32, 32) r, Bit#(26) addr_loc);
            action
                // Filter local addresses
                if (!isDmemAddrRange(addr_loc)) begin
                    // Send empty response, and deq request fifo
                    inflight_rq.enq(DUMMY);
                end else begin
                    // Forward to dmem
                    dbram.portA.request.put(BRAMRequestBE{writeen: 'hF, responseOnWrite: False, address: (extend(addr_loc)>>2), datain: r.data});
                    inflight_rq.enq(DMEM);
                end
            endaction
        endfunction


        // response for DMEM writes
        rule dmemReadResponse if (inflight_rq.first() == DMEM);
            inflight_rq.deq();
            let resp_data <- dbram.portA.response.get();
            responses.enq(resp_data);
        endrule

        // dummy response for erroneous accesses
        rule dmemDummyResponse if (inflight_rq.first() == DUMMY);
            inflight_rq.deq();
            // recognizable value for errors
            responses.enq('hdeadbeef);
        endrule

        /*
        * Request Router
        * - Forward requests to the appropriate memory.
        * - Handle only one request in flight at a time to keep order of responses simple.
        * - Use 2 bits [27:26] to select target.
        */

        rule wishboneRouter;
            // get request from FIFO and dissect it into routing part and address of the component
            let r = requests.first();
            requests.deq();
            Bit#(2) msbs = r.address[27:26];
            Bit#(26) addr_loc = r.address[25:0];

            // writes into special region triggers core to run
            if (r.address == fromInteger(valueOf(WB_OFFSET_START)) << 26) rst_active <= False;

            // Use MSBs to determine destination of a request
            case (msbs)
                fromInteger(valueOf(WB_OFFSET_IMEM)):        toImem(r, addr_loc);
                fromInteger(valueOf(WB_OFFSET_DMEM)):        toDmem(r, addr_loc);
            endcase
        endrule


        /*
        * SCOoOTER instruction access
        */


        // FETCH side
        // IMEM requests
        // Only allowed once program has been loaded
        // So we effectively stall the processor until loading is complete
        rule ifuread if (!rst_active);
            let r <- core.imem_r.request.get();
            
            // Move from byte addressing to word addressing
            // since the memories are word-addressed 
            let addr = r;
            let idx = (pack(addr)>>2);


            ibram.portA.request.put(BRAMRequestBE{
                writeen: 0,
                responseOnWrite: True,
                address: idx,
                datain: ?
            });
          endrule

        // response to FETCH side of SCOoOTER
        rule ifuresp if (!rst_active);
            let r <- ibram.portA.response.get();
            core.imem_r.response.put(r);
        endrule

        /*
         SCOoOTER data access
        */

        // tag whether we excpect a read or write response next
        FIFO#(AccType) next_mem_access <- mkPipelineFIFO();


        // LOAD/STORE read connection to data memory
        rule dfuread if (!rst_active);
            let r <- core.dmem_r.request.get();
            // convert to word address
            // and remove offset
            let addr = r;
            let idx = (addr-fromInteger(valueOf(BASE_DMEM)))>>2;
            dbram.portA.request.put(BRAMRequestBE{
                writeen: 0,
                responseOnWrite: True,
                address: pack(idx),
                datain: ?
            });
            next_mem_access.enq(RD);
        endrule

        // LOAD/STORE read response from data memory
        rule dfuresp if (next_mem_access.first() == RD);
            next_mem_access.deq();
            let r <- dbram.portA.response.get();
            core.dmem_r.response.put(r);
        endrule

        // LOAD/STORE write connection to data memory
        (*descending_urgency="wishboneRouter, dfuwrite, ifuread"*)
        rule dfuwrite;
            let r <- core.dmem_w.request.get();
            let addr = tpl_1(r);
            let data = tpl_2(r);
            let strb = tpl_3(r);
            // generate word address
            // and remove offset
            let idx = (addr-fromInteger(valueOf(BASE_DMEM)))>>2;
            dbram.portA.request.put(BRAMRequestBE{
                writeen: strb,
                responseOnWrite: True,
                address: pack(idx),
                datain: data
            });
            next_mem_access.enq(WR);
        endrule

        // LOAD/STORE write response from data memory
        rule dfuwresp if (next_mem_access.first() == WR);
            let r <- dbram.portA.response.get();
            core.dmem_w.response.put(0);
            next_mem_access.deq();
        endrule

        interface Server ext_bus;
            interface Put request = toPut(requests);
            interface Get response = toGet(responses);
        endinterface

        // GPIOs and interrupt pins
        interface gpio_in  = dmem.gpio_in;
        interface gpio_out = dmem.gpio_out;
        interface irq_vex  = dmem.irq_vex;

    endmodule

endpackage
