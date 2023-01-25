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
            let testCustom <- mkTestProgram("../../testPrograms/embench/statemate/32bit/bsv_hex/statemate_256.bsv", "../../testPrograms/embench/statemate/32bit/bsv_hex/statemate-data_32.bsv", "custom", 'hffffffff, 'hffffffff);

            rule start;
                testCustom.go();
            endrule
        `endif
    endmodule

endpackage
		    