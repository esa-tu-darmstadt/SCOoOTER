package Testbench;
    `ifndef CUSTOM_TB
        import TestsMulti::*;
    `endif
    import TestbenchProgram::*;

    (* synthesize *)
    module [Module] mkTestbench();

        `ifndef CUSTOM_TB
            let testsISA <- mkTestsISA();
        `endif

        `ifdef CUSTOM_TB
            let testCustom <- mkTestProgram("../../testPrograms/custom/test_ext_int/bsv/test_ext_int_96.bsv",
                "../../testPrograms/custom/test_ext_int/bsv/test_ext_int-data_32.bsv", 
                "custom", 
                'hffffffff, 
                'hffffffff);

            rule start;
                testCustom.go();
            endrule
        `endif
    endmodule

endpackage
