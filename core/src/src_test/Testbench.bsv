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
            let testCustom <- mkTestProgram("../../testPrograms/isa/32um/bsv_hex/rv32um-p-mulh_128.bsv", "custom", 'hffffffff, 'hffffffff);

            rule start;
                testCustom.go();
            endrule
        `endif
    endmodule

endpackage
