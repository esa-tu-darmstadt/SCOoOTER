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
            let testCustom <- mkTestProgram("../../testPrograms/isa/32ui/bsv_hex/rv32ui-p-lbu_256.bsv", "../../testPrograms/isa/32ui/bsv_hex/rv32ui-p-lbu-data_32.bsv", "custom", 'hffffffff, 'hffffffff);

            rule start;
                testCustom.go();
            endrule
        `endif
    endmodule

endpackage
