package TestsMainTest;
    import StmtFSM :: *;
    import TestHelper :: *;
    import SCOOOTER_riscv :: *;
    import Interfaces :: *;
    import Types :: *;
    import BlueAXI :: *;
    import Connectable :: *;
    import GetPut :: *;
    import BRAM :: *;

    (* synthesize *)
    module [Module] mkTestsMainTest(TestHandler);

        Top dut <- mkSCOOOTER_riscv();

        AXI4_Slave_Rd#(XLEN, IFUWIDTH, 0, 0) iram_axi <- mkAXI4_Slave_Rd(0, 0);

	    mkConnection(iram_axi.fab ,dut.ifu_axi);

        BRAM_Configure cfg_i = defaultValue;
        cfg_i.allowWriteResponseBypass = False;
        cfg_i.loadFormat = tagged Hex "../../testPrograms/isa/32ui/bsv_hex/rv32ui-p-add.bsv.txt";
        cfg_i.latency = 1;
        BRAM1Port#(WORD, IFUWORD) ibram <- mkBRAM1Server(cfg_i);


        rule ifuread;
    		let r <- iram_axi.request.get();
            ibram.portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: r.addr,
                datain: ?
            });


    		
  	    endrule

        rule ifuresp;
            let r <- ibram.portA.response.get;
            iram_axi.response.put(AXI4_Read_Rs {data: r, id: 0, resp: OKAY, last: True, user: 0});
        endrule

    endmodule

endpackage
