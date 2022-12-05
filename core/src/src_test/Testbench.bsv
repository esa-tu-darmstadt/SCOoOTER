package Testbench;
    import Vector :: *;
    import StmtFSM :: *;

    import TestHelper :: *;

    // Project Modules
    import `RUN_TEST :: *;

    typedef 1 TestAmount;

    (* synthesize *)
    module [Module] mkTestbench();
        Vector#(TestAmount, TestHandler) testVec;
        testVec[0] <- `TESTNAME ();
    endmodule

endpackage
