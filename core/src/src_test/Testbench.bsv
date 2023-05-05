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
            let testCustom <- mkTestProgram("../../testPrograms/embench/aha-mont64/32bit/bsv_hex/aha-mont64_96.bsv", 
		    "../../testPrograms/embench/aha-mont64/32bit/bsv_hex/aha-mont64-data_32.bsv", 
                "custom", 
                'hffffffff, 
                'hffffffff);

            rule start;
                testCustom.go();
            endrule
        `endif
    endmodule

endpackage
