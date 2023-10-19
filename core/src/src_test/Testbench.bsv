package Testbench;
    `ifndef CUSTOM_TB
        `ifndef COREV_TB
            import TestsMulti::*;
        `endif
    `endif
    import TestbenchProgram::*;
    import Types::*;
    import TestFunctions::*;

    (* synthesize *)
    module [Module] mkTestbench();

        `ifndef CUSTOM_TB
            `ifndef COREV_TB
                let testsISA <- mkTestsISA();
            `endif
        `endif

        `ifdef CUSTOM_TB
            let testCustom <- mkTestProgram("../../testPrograms/priv/bsv_hex/misalign-bgeu-01" + "_" + select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", 
		        "../../testPrograms/priv/bsv_hex/misalign-bgeu-01" + "-data_32.bsv", 
                "custom", 
                'hffffffff, 
                'hffffffff);

            rule start;
                testCustom.go();
            endrule
        `endif

        `ifdef COREV_TB
            let testCustom <- mkTestProgram("../../program/test_" + select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", 
		        "../../program/test-data_32.bsv", 
                "custom", 
                'hffffffff, 
                'hffffffff);

            rule start;
                testCustom.go();
            endrule
        `endif
    endmodule

endpackage
