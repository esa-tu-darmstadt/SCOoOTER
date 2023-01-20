package TestsISA;
    import StmtFSM::*;
    import TestbenchProgram::*;
    import BlueLibTests :: *;
    import Assertions :: *;
    import Types::*;

    typedef struct {
	    String name_unit;
	    String isa;
    } Test_unit;

    function String select_fitting_prog_binary(Integer width);
        return case (width)
            1: "32";
            2: "64";
            3: "96";
            4: "128";
            5: "160";
            6: "192";
            7: "224";
            8: "256";
        endcase;
    endfunction


    (* synthesize *)
    module mkTestsISA(Empty) provisos(
    );

        function inst_test_ISA(Test_unit in) = mkTestProgram("../../testPrograms/isa/"+in.isa+"/bsv_hex/"+in.name_unit+"_"+ select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", 
		    "../../testPrograms/isa/"+in.isa+"/bsv_hex/"+in.name_unit+"-data_"+ "32" + ".bsv", 
		    in.name_unit,
		    8000,
            1);


        List#(Test_unit) test_units = Nil;

        //integer
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

        //Div
        test_units = List::cons(Test_unit {isa: "32um", name_unit: "rv32um-p-div"}, test_units);
		test_units = List::cons(Test_unit {isa: "32um", name_unit: "rv32um-p-divu"}, test_units);
		test_units = List::cons(Test_unit {isa: "32um", name_unit: "rv32um-p-rem"}, test_units);
		test_units = List::cons(Test_unit {isa: "32um", name_unit: "rv32um-p-remu"}, test_units);

        //Mul
		test_units = List::cons(Test_unit {isa: "32um", name_unit: "rv32um-p-mul"}, test_units);
		test_units = List::cons(Test_unit {isa: "32um", name_unit: "rv32um-p-mulh"}, test_units);
		test_units = List::cons(Test_unit {isa: "32um", name_unit: "rv32um-p-mulhsu"}, test_units);
		test_units = List::cons(Test_unit {isa: "32um", name_unit: "rv32um-p-mulhu"}, test_units);

        //AMO




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
            let err_msg = $format("Not all ISA tests were successful");
            assertEquals(8, fail+hang, err_msg);
            $finish();
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
                                    printColor(BLUE, $format("%3d [TB] +++ PASSED +++ "+tests[testCounter].test_name, left_l));
                                    pass_l = pass_l + 1;
                                    end
                                else begin
                                    printColor(RED, $format("%3d [TB] +++ FAILED +++ "+tests[testCounter].test_name + " Exp: %0d Got: %0d", left_l, tests[testCounter].return_value_exp, tests[testCounter].return_value));
                                    fail_l = fail_l + 1;
                                end
                            end else begin
                                printColor(RED, $format("%3d [TB] +++ HANGS  +++ "+tests[testCounter].test_name, left_l));
                                hang_l = hang_l + 1;
                                end
                        end				
                    end
            left <= left_l;
            hang <= hang_l;
            pass <= pass_l;
            fail <= fail_l;
        endrule

    endmodule

endpackage
