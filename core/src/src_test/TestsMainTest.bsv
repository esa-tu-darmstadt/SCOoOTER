package TestsMainTest;
    import StmtFSM::*;
    import TestHelper::*;
    import TestbenchProgram::*;

    typedef struct {
	    String name_unit;
	    String isa;
    } Test_unit;


    (* synthesize *)
    module [Module] mkTestsMainTest(TestHandler) provisos(
    );

        function inst_test_ISA(Test_unit in) = mkTestProgram("../../testPrograms/isa/"+in.isa+"/bsv_hex/"+in.name_unit+".bsv.txt", 
		    //"../../testPrograms/isa/"+in.isa+"/bsv_hex/"+in.name_unit+"-data.bsv.txt", 
		    in.name_unit,
		    2000,
            1);


        List#(Test_unit) test_units = Nil;

        test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-add"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-addi"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-and"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-andi"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-auipc"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-beq"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-bge"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-bgeu"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-blt"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-bltu"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-bne"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-jal"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-jalr"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-lb"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-lbu"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-lh"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-lhu"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-lui"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-lw"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-or"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-ori"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-sb"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-sh"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-sll"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-slli"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-slt"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-slti"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-sltiu"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-sltu"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-sra"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-srai"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-srl"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-srli"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-sub"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-sw"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-xor"}, test_units);
		test_units = List::cons(Test_unit {isa: "32ui", name_unit: "rv32ui-p-xori"}, test_units);


        List#(TestProgIFC) inst_test_modules <- List::mapM(inst_test_ISA, test_units);

        List#(List#(TestProgIFC)) test_lists = Nil;
        test_lists = List::cons(inst_test_modules, test_lists);
        List#(TestProgIFC) tests = List::concat(test_lists);

        Integer testAmount = List::length(tests);
        Reg#(Int#(32)) left <- mkReg(fromInteger(testAmount));
        Reg#(Int#(32)) pass <- mkReg(0);
        Reg#(Int#(32)) fail <- mkReg(0);
        Reg#(Int#(32)) hang <- mkReg(0);
        List#(Reg#(Bool)) notFinished <- List::replicateM(testAmount, mkReg(True));

        rule start_tests;
            for(Integer i = 0; i < testAmount; i=i+1)
                tests[i].go();
        endrule

        rule stop_test(left == 0);
            $display("Elapsed %0d tests", testAmount);
            $display("Passed: %0d Broken: %0d Stuck: %0d", pass, fail, hang);
            $finish;
        endrule

        rule evaluate_results;
            $fflush();
            Int#(32) left_l = left;
            Int#(32) pass_l = pass;
            Int#(32) fail_l = fail;
            Int#(32) hang_l = hang;
            for(Integer testCounter = 0;
                testCounter < testAmount;
                testCounter = testCounter + 1)
                    begin
                        if(tests[testCounter].done() && notFinished[testCounter]) begin
                            notFinished[testCounter] <= False;
                            left_l = left_l - 1;
                            if (tests[testCounter].state() == Finished) begin
                                if(tests[testCounter].return_value == tests[testCounter].return_value_exp) begin
                                    $display("%3d [TB] +++ PASSED +++ "+tests[testCounter].test_name, left_l);
                                    pass_l = pass_l + 1;
                                    end
                                else begin
                                    $display("%3d [TB] +++ FAILED +++ "+tests[testCounter].test_name + " Exp: %0d Got: %0d", left_l, tests[testCounter].return_value_exp, tests[testCounter].return_value);
                                    fail_l = fail_l + 1;
                                end
                            end else begin
                                $display("%3d [TB] +++ HANGS  +++ "+tests[testCounter].test_name, left_l);
                                hang_l = hang_l + 1;
                                end
                        end				
                    end
            left <= left_l;
            hang <= hang_l;
            pass <= pass_l;
            fail <= fail_l;
        endrule





        /*let dut <- mkSCOOOTER_riscv();

        AXI4_Slave_Rd#(XLEN, ifuwidth, 0, 0) iram_axi <- mkAXI4_Slave_Rd(0, 0);
        AXI4_Slave_Wr#(XLEN, XLEN, 0, 0) dram_axi <- mkAXI4_Slave_Wr(0, 0, 0);

	    mkConnection(iram_axi.fab ,dut.imem_axi);
        mkConnection(dram_axi.fab ,dut.dmem_axi);

        BRAM_Configure cfg_i = defaultValue;
        cfg_i.allowWriteResponseBypass = False;
        cfg_i.loadFormat = tagged Hex "../../testPrograms/isa/32ui/bsv_hex/rv32ui-p-add.bsv.txt";
        cfg_i.latency = 1;
        BRAM1Port#(Bit#(XLEN), Bit#(ifuwidth)) ibram <- mkBRAM1Server(cfg_i);


        rule ifuread;
    		let r <- iram_axi.request.get();
            ibram.portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: (r.addr>>2)/fromInteger(valueOf(IFUINST)),
                datain: ?
            });
  	    endrule

        rule ifuresp;
            let r <- ibram.portA.response.get;
            iram_axi.response.put(AXI4_Read_Rs {data: r, id: 0, resp: OKAY, last: True, user: 0});
        endrule

        Reg#(Maybe#(AXI4_Write_Rq_Addr#(XLEN, 0, 0))) w_request <- mkReg(tagged Invalid);
    
  	    rule handleWriteRequest if(w_request matches tagged Invalid);
        	let r <- dram_axi.request_addr.get();
        	w_request <= tagged Valid r;
        	$display("Tb: Request for %x %d", r.addr, r.burst_length);
    	endrule

    	rule returnWriteValue if(w_request matches tagged Valid .v);
        	let r <- dram_axi.request_data.get();
        	$display("Tb: Got write request %x %b", r.data, r.strb);
            w_request <= tagged Invalid;
            dram_axi.response.put(AXI4_Write_Rs {id: 0, resp: OKAY, user:0});
    	endrule*/




    endmodule

endpackage
