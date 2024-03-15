package Testbench;


    /*
    
    Toplevel testbench module. Instantiates
    - (a) single testbenchProgram in case a single test is executed
    - (b) TestsMulti in case many tests are to be executed
    
    */

    // only import TestsMulti if needed - takes long to build
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

        // always flush all printed info to avoid loosing any
        rule flush_prints;
            $fflush();
        endrule

        // if no single-program test is executed, run multi-program test
        `ifndef CUSTOM_TB
            `ifndef COREV_TB
                let testsISA <- mkTestsISA();
            `endif
        `endif

        // custom TB - single program | Program binary should be set here
        `ifdef CUSTOM_TB
            let testCustom <- mkTestProgram("../../testPrograms/isa/32ui/bsv_hex/rv32ui-p-xor" + "_" + select_fitting_prog_binary(valueOf(IFUINST)) + ".bsv", 
		        "../../testPrograms/isa/32ui/bsv_hex/rv32ui-p-xor" + "-data_32.bsv", 
                "custom", 
                'hffffffff, 
                'hffffffff);

            rule start;
                testCustom.go();
            endrule
        `endif

        // CORE_V_VERIF TB - program binary is passed via commandline
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
