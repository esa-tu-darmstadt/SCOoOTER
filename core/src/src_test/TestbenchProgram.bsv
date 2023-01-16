package TestbenchProgram;
    import StmtFSM :: *;
    import SCOOOTER_riscv :: *;
    import Interfaces :: *;
    import Types :: *;
    import BlueAXI :: *;
    import Connectable :: *;
    import GetPut :: *;
    import BRAM :: *;
    import DefaultValue::*;

    typedef 'h11000010 RV_CONTROLLER_RETURN_ADDRESS;
    typedef 'h11004000 RV_CONTROLLER_INTERRUPT_ADDRESS;


    typedef enum {
        Finished,
        Hangs
    } State deriving(Bits, Eq);

    interface TestProgIFC;
        method Bool done();
        method State state();
        method Bit#(XLEN) return_value();
        method Action go();
        method Bit#(32) return_value_exp();
        method String test_name();
    endinterface

    module mkTestProgram#(String imem_file, String test_name, Integer max_ticks, Bit#(32) exp_return_value)(TestProgIFC) provisos(
        Mul#(XLEN, IFUINST, ifuwidth)
    );

        Reg#(Bool) done_r <- mkReg(False);
        Reg#(Bool) start_r <- mkReg(False);
        Reg#(State) state_r <- mkRegU();
        Reg#(Bit#(XLEN)) return_r <- mkRegU();
        Reg#(UInt#(XLEN)) count_r <- mkReg(0);

        let dut <- mkSCOOOTER_riscv();

        AXI4_Slave_Rd#(XLEN, ifuwidth, 0, 0) iram_axi <- mkAXI4_Slave_Rd(0, 0);
        AXI4_Slave_Wr#(XLEN, XLEN, 0, 0) dram_axi <- mkAXI4_Slave_Wr(0, 0, 0);

	    mkConnection(iram_axi.fab ,dut.imem_axi);
        mkConnection(dram_axi.fab ,dut.dmem_axi);

        BRAM_Configure cfg_i = defaultValue;
        cfg_i.allowWriteResponseBypass = False;
        cfg_i.loadFormat = tagged Hex imem_file;
        cfg_i.latency = 1;
        BRAM1Port#(Bit#(XLEN), Bit#(ifuwidth)) ibram <- mkBRAM1Server(cfg_i);

        rule count if (start_r && count_r <= fromInteger(max_ticks));
            count_r <= count_r + 1;
        endrule

        rule cutoff if(count_r > fromInteger(max_ticks));
            done_r <= True;
            state_r <= Hangs;
        endrule

        rule ifuread if (start_r && !done_r && count_r <= fromInteger(max_ticks));
    		let r <- iram_axi.request.get();
            ibram.portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: (r.addr>>2)/fromInteger(valueOf(IFUINST)),
                datain: ?
            });
  	    endrule

        rule ifuresp;
            let r <- ibram.portA.response.get();
            iram_axi.response.put(AXI4_Read_Rs {data: r, id: 0, resp: OKAY, last: True, user: 0});
        endrule

        Reg#(Maybe#(AXI4_Write_Rq_Addr#(XLEN, 0, 0))) w_request <- mkReg(tagged Invalid);
    
  	    rule handleWriteRequest if(w_request matches tagged Invalid);
        	let r <- dram_axi.request_addr.get();
        	w_request <= tagged Valid r;
    	endrule

    	rule returnWriteValue if(w_request matches tagged Valid .v &&& count_r <= fromInteger(max_ticks));
        	let r <- dram_axi.request_data.get();
            let addr = w_request.Valid.addr;
            let data = r.data;

            //RVController emulation
            // TODO: switch case
            if(addr == fromInteger(valueOf(RV_CONTROLLER_INTERRUPT_ADDRESS))) begin
                done_r <= True;
                state_r <= Finished;
            end else if (addr == fromInteger(valueOf(RV_CONTROLLER_RETURN_ADDRESS))) begin
                return_r <= data;
            end
            w_request <= tagged Invalid;
            dram_axi.response.put(AXI4_Write_Rs {id: 0, resp: OKAY, user:0});
    	endrule

        method Bool done() = done_r._read();
        method State state() = state_r._read();
        method Bit#(XLEN) return_value() = return_r._read();
        method Action go();
            start_r <= True;
        endmethod
        method Bit#(32) return_value_exp() = exp_return_value;
        method String test_name() = test_name;
    endmodule

endpackage
