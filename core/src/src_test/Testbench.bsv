package Testbench;
    `ifdef ISA_TB
        import TestsISA::*;
    `endif
    import TestbenchProgram::*;

    (* synthesize *)
    module [Module] mkTestbench();

        `ifdef ISA_TB
            let testsISA <- mkTestsISA();
        `endif

        `ifdef CUSTOM_TB
            let testCustom <- mkTestProgram("../../testPrograms/isa/32ui/bsv_hex/rv32ui-p-sw_256.bsv", "../../testPrograms/isa/32ui/bsv_hex/rv32ui-p-sw-data_32.bsv", "custom", 'hffffffff, 'hffffffff);

            rule start;
                testCustom.go();
            endrule
        `endif
    endmodule

endpackage
