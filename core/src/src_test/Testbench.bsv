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
            let testCustom <- mkTestProgram("../../tools/riscv-arch-test/work/rv32i_m/privilege/ecall_32.bsv",
                "../../tools/riscv-arch-test/work/rv32i_m/privilege/ecall-data_32.bsv", 
                "custom", 
                'hffffffff, 
                'hffffffff);

            rule start;
                testCustom.go();
            endrule
        `endif
    endmodule

endpackage
