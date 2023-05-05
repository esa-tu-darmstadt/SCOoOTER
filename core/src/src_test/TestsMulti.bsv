package TestsMulti;
    import StmtFSM::*;
    import TestbenchProgram::*;
    import BlueLibTests :: *;
    import Assertions :: *;
    import Types::*;
    import BuildList::*;
    import TestFunctions::*;

    typedef struct {
	    String name_unit;
	    String isa;
    } Test_unit;

    (* synthesize *)
    module mkTestsISA(Empty) provisos(
    );

        function inst_test_priv(String name_unit) = mkTestProgram("../../testPrograms/priv/bsv_hex/"+name_unit+"_"+ select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", 
		    "../../testPrograms/priv/bsv_hex/"+name_unit+"-data_32.bsv", 
		    name_unit,
		    100000,
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
            assertEquals(0, fail+hang, err_msg);
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
                                    `ifdef EVA_BR
                                        printColor(BLUE, $format("%3d [TB] +++ PASSED +++ " + " took: %8d ticks correct BP (br): %d wrong BP (br): %d correct BP (j): %d wrong BP (j): %d " + tests[testCounter].test_name, left_l, tests[testCounter].count(), tests[testCounter].correct_pred_br(), tests[testCounter].wrong_pred_br(), tests[testCounter].correct_pred_j(), tests[testCounter].wrong_pred_j()));
                                    `else
                                        printColor(BLUE, $format("%3d [TB] +++ PASSED +++ " + tests[testCounter].test_name + " took: %8d ticks", left_l, tests[testCounter].count()));
                                    `endif
                                    pass_l = pass_l + 1;
                                    end
                                else begin
                                    printColor(RED, $format("%3d [TB] +++ FAILED +++ " + tests[testCounter].test_name + " took: %8d ticks Exp: %0d Got: %0d", left_l, tests[testCounter].count(), tests[testCounter].return_value_exp, tests[testCounter].return_value));
                                    fail_l = fail_l + 1;
                                end
                            end else begin
                                printColor(RED, $format("%3d [TB] +++ HANGS  +++ " + tests[testCounter].test_name + " ", left_l));
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
