package TestsMulti;
    
    /*
    
    Execute multiple test binaries / entire test suites
    
    */

    import StmtFSM::*;
    import TestbenchProgram::*;
    import BlueLibTests :: *;
    import Assertions :: *;
    import Types::*;
    import TestFunctions::*;
    import BuildList::*;

    // struct to store info about test
    typedef struct {
	    String name_unit;
	    String isa;
    } Test_unit;

    (* synthesize *)
    module mkTestsISA(Empty) provisos(
    );

        // helper functions to map test name to instance

        function inst_test_priv(String name_unit) = mkTestProgram("../../testPrograms/priv/bsv_hex/"+name_unit+"_"+ select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", 
		    "../../testPrograms/priv/bsv_hex/"+name_unit+"-data_32.bsv", 
		    name_unit,
		    500000,
            'haaaaaaaa);

        function inst_test_ISA(Test_unit in) = mkTestProgram("../../testPrograms/isa/"+in.isa+"/bsv_hex/"+in.name_unit+"_"+ select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", 
		    "../../testPrograms/isa/"+in.isa+"/bsv_hex/"+in.name_unit+"-data_32.bsv", 
		    in.name_unit,
		    100000,
            1);

        function inst_test_embench(String name_unit) = mkTestProgram("../../testPrograms/embench/"+name_unit+"/32bit/bsv_hex/"+name_unit+"_"+ select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", 
		    "../../testPrograms/embench/"+name_unit+"/32bit/bsv_hex/"+name_unit+"-data_32.bsv", 
		    name_unit,
		    'hffffffff-1,
            1);

        function inst_test_amo(String name_unit) = mkTestProgram("../../testPrograms/custom/test_multi_core_"+name_unit+"/bsv/test_multi_core_"+name_unit+"_"+ select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", 
		    "../../testPrograms/custom/test_multi_core_"+name_unit+"/bsv/test_multi_core_"+name_unit+"-data_32.bsv", 
		    name_unit,
		    'hffffffff-1,
            1);

        function inst_test_lrsc(String name_unit) = mkTestProgram("../../testPrograms/amo/bsv_hex/"+name_unit+"_"+ select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", 
		    "../../testPrograms/amo/bsv_hex/"+name_unit+"-data_32.bsv", 
		    name_unit,
		    'hffffffff-1,
            'h00000800);


        // depending on selected test suite, generate TestbenchProgram instances with all cases
        // inst_test_modules will contain one TestbenchProgram instance per test case
        


        `ifdef ISA_TB

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
            test_units = List::cons(Test_unit {isa: "32ua", name_unit: "rv32ua-p-amoadd_w"}, test_units);
            test_units = List::cons(Test_unit {isa: "32ua", name_unit: "rv32ua-p-amoand_w"}, test_units);
            test_units = List::cons(Test_unit {isa: "32ua", name_unit: "rv32ua-p-amomaxu_w"}, test_units);
            test_units = List::cons(Test_unit {isa: "32ua", name_unit: "rv32ua-p-amomax_w"}, test_units);
            test_units = List::cons(Test_unit {isa: "32ua", name_unit: "rv32ua-p-amominu_w"}, test_units);
            test_units = List::cons(Test_unit {isa: "32ua", name_unit: "rv32ua-p-amomin_w"}, test_units);
            test_units = List::cons(Test_unit {isa: "32ua", name_unit: "rv32ua-p-amoor_w"}, test_units);
            test_units = List::cons(Test_unit {isa: "32ua", name_unit: "rv32ua-p-amoswap_w"}, test_units);
            test_units = List::cons(Test_unit {isa: "32ua", name_unit: "rv32ua-p-amoxor_w"}, test_units);
            test_units = List::cons(Test_unit {isa: "32ua", name_unit: "rv32ua-p-lrsc"}, test_units);

            List#(TestProgIFC) inst_test_modules <- List::mapM(inst_test_ISA, test_units);
        `endif

        `ifdef PRIV_TB
            List#(String) test_names = list(
                "ebreak",
                "ecall",
                "misalign1-jalr-01",
                "misalign2-jalr-01",
                "misalign-beq-01",
                "misalign-bge-01",
                "misalign-bgeu-01",
                "misalign-blt-01",
                "misalign-bltu-01",
                "misalign-bne-01",
                "misalign-jal-01",
                "misalign-lh-01",
                "misalign-lhu-01",
                "misalign-lw-01",
                "misalign-sh-01",
                "misalign-sw-01"
            );

            List#(TestProgIFC) inst_test_modules <- List::mapM(inst_test_priv, test_names);
        `endif

        `ifdef AMO_TB
            List#(String) test_names = list(
                "amoadd",
                "amoand",
                "amoswap",
                "amomax",
                "amomin",
                "amoor",
                "amoxor"
            );

            let amo_rv_test <- inst_test_ISA(Test_unit {isa: "32ua", name_unit: "rv32ua-p-lrsc"});
            List#(TestProgIFC) inst_test_modules <- List::mapM(inst_test_amo, test_names);
            inst_test_modules = List::cons(amo_rv_test, inst_test_modules);
        `endif

        `ifdef LRSC_TB
            List#(String) test_names = list(
                "riscv_amo_test_0",
                "riscv_amo_test_1"
            );
            List#(TestProgIFC) inst_test_modules <- List::mapM(inst_test_lrsc, test_names);
        `endif

        `ifdef EMBENCH_TB

            List#(String) test_names = list(
                "statemate",
                "aha-mont64",
                "cubic",
                "edn",
                "huffbench",
                "matmult-int",
                "minver",
                "nbody",
                "nettle-aes",
                "nettle-sha256",
                "nsichneu",
                "picojpeg",
                "qrduino",
                "sglib-combined",
                "slre",
                "st",
                "ud",
                "wikisort"
            );

            List#(TestProgIFC) inst_test_modules <- List::mapM(inst_test_embench, test_names);

        `endif

        // get amount of tests
        Integer testAmount = List::length(inst_test_modules);
        // counter registers for running, passed, failed and timeouted tests
        Reg#(Int#(32)) left <- mkReg(fromInteger(testAmount));
        Reg#(Int#(32)) pass <- mkReg(0);
        Reg#(Int#(32)) fail <- mkReg(0);
        Reg#(Int#(32)) hang <- mkReg(0);
        // one bool per test to signify if it is still running
        List#(Reg#(Bool)) notFinished <- List::replicateM(testAmount, mkReg(True));

        // launch all tests
        rule start_tests;
            for(Integer i = 0; i < testAmount; i=i+1)
                inst_test_modules[i].go();
        endrule

        // end simulation if all tests are done
        rule stop_test(left == 0);
            $display("Elapsed %0d tests", testAmount);
            $display("Passed: %0d Broken: %0d Stuck: %0d", pass, fail, hang);
            let err_msg = $format("Not all ISA tests were successful");
            //assertEquals(0, fail+hang, err_msg);
            $finish();
        endrule

        // evaluate state of all tests
        rule evaluate_results;
            $fflush();
            Int#(32) left_l = left;
            Int#(32) pass_l = pass;
            Int#(32) fail_l = fail;
            Int#(32) hang_l = hang;
            for(Integer testCounter = 0;
                testCounter < testAmount;
                testCounter = testCounter + 1) // loop through tests
                    begin
                        if(inst_test_modules[testCounter].done() && notFinished[testCounter]) begin // if the test is done but has not been handled yet
                            notFinished[testCounter] <= False; // set flag that test was handled
                            left_l = left_l - 1; // secrement amount of remaining tests
                            if (inst_test_modules[testCounter].state() == Finished) begin // if the test finished gracefully
                                // check return value and print pass/fail message
                                if(inst_test_modules[testCounter].return_value == inst_test_modules[testCounter].return_value_exp) begin
                                    `ifdef EVA_BR
                                        printColor(BLUE, $format("%3d [TB] +++ PASSED +++ " + " took: %8d ticks correct BP (br): %d wrong BP (br): %d correct BP (j): %d wrong BP (j): %d " + inst_test_modules[testCounter].test_name, left_l, inst_test_modules[testCounter].count(), inst_test_modules[testCounter].correct_pred_br(), inst_test_modules[testCounter].wrong_pred_br(), inst_test_modules[testCounter].correct_pred_j(), inst_test_modules[testCounter].wrong_pred_j()));
                                    `else
                                        printColor(BLUE, $format("%3d [TB] +++ PASSED +++ " + inst_test_modules[testCounter].test_name + " took: %8d ticks", left_l, inst_test_modules[testCounter].count()));
                                    `endif
                                    pass_l = pass_l + 1;
                                    end
                                else begin
                                    printColor(RED, $format("%3d [TB] +++ FAILED +++ " + inst_test_modules[testCounter].test_name + " took: %8d ticks Exp: %0d Got: %0d", left_l, inst_test_modules[testCounter].count(), inst_test_modules[testCounter].return_value_exp, inst_test_modules[testCounter].return_value));
                                    fail_l = fail_l + 1;
                                end
                            end else begin
                                // if test did not finish gracefully, treat it as hung up
                                printColor(RED, $format("%3d [TB] +++ HANGS  +++ " + inst_test_modules[testCounter].test_name + " ", left_l));
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
