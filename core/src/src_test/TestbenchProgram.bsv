package TestbenchProgram;
    import StmtFSM :: *;
    import IDMemAdapter :: *;
    import Interfaces :: *;
    import Types :: *;
    import BlueAXI :: *;
    import Connectable :: *;
    import GetPut :: *;
    import BRAM :: *;
    import DefaultValue::*;
    import FIFO::*;
    import SpecialFIFOs::*;
    import BRamImem::*;
    import BRamDmem::*;

    // RVController emulation defines
    typedef 'h11000010 RV_CONTROLLER_RETURN_ADDRESS;
    typedef 'h11004000 RV_CONTROLLER_INTERRUPT_ADDRESS;
    typedef 'h11008000 RV_CONTROLLER_PRINT_ADDRESS;

    // Exit codes of the simulation
    typedef enum {
        Finished,
        Hangs
    } State deriving(Bits, Eq);

    // Test interface
    interface TestProgIFC;
        method Bool done(); // True if test is done
        method State state(); // returns if the test hung or was successful
        method Bit#(XLEN) return_value(); // returns the data written to RVController
        method Action go(); // start the test

        // could be pulled out to testbench module to make this synthesizable
        method Bit#(32) return_value_exp(); // wrapps excpected return value for assertions
        method String test_name(); // wrapps test name for display
        method UInt#(XLEN) count(); // returns elapsed clock cycles

        `ifdef EVA_BR
            method UInt#(XLEN) correct_pred_j;
            method UInt#(XLEN) wrong_pred_j;
            method UInt#(XLEN) correct_pred_br;
            method UInt#(XLEN) wrong_pred_br;
        `endif
    endinterface


    // simulates the periphery of the core
    module mkTestProgram#(String imem_file, String dmem_file, String test_name, Integer max_ticks, Bit#(32) exp_return_value)(TestProgIFC) provisos(
        // the instruction bus is as wide as the number of instructions fetched per cycle times the width of an instruction
        Mul#(XLEN, IFUINST, ifuwidth),
        // BRAMs are word addressed, thus we calculate the size in words
        Div#(SIZE_DMEM, 4, bram_word_num_t),
        Log#(NUM_CPU, cpu_idx_t),
        Add#(cpu_idx_t, 1, cpu_and_amo_idx_t)
    );

        // status flags
        Reg#(State) state_r <- mkReg(Finished);
        // counts erxecution ticks for cutoff and banchmarking
        Reg#(UInt#(XLEN)) count_r <- mkReg(0);


        let dut <- mkIDMemAdapter();

        rule interrupt;
            dut.ext_int(count_r%'h3000 == 0 && count_r%'h6000 != 0 && count_r%'h8000 != 0 ? unpack({1'b1, 0}): unpack(0));
            dut.sw_int(count_r%'h8000 == 0 ? unpack({1'b1, 0}): unpack(0));
        endrule

        // INSTRUCTION MEMORY
        let imem <- mkBramImem(imem_file);
        mkConnection(imem.mem, dut.imem_r);

        // DATA MEMORY
        let dmem <- mkBramDmem(dmem_file);
        mkConnection(dmem.memory_bus.mem_r, dut.dmem_r);
        mkConnection(dmem.memory_bus.mem_w, dut.dmem_w);

        `ifdef CUSTOM_TB
            rule end_exec if (state_r != None);
                $display("Took: ", fshow(count_r));
                $display("result: ", fshow(return_r));
                `ifdef EVA_BR
                    $display("correct pred (br): ", dut.correct_pred_br);
                    $display("wrong pred (br): ", dut.wrong_pred_br);
                    $display("correct pred (j): ", dut.correct_pred_j);
                    $display("wrong pred (j): ", dut.wrong_pred_j);
                `endif
                $finish();
            endrule
        `endif

        
        // HOUSEKEEPING

        // increment counter
        rule increment_count if (count_r <= fromInteger(max_ticks));
            count_r <= count_r + 1;
        endrule

        // stop CPU if counter overflows
        rule cutoff if(count_r > fromInteger(max_ticks));
            state_r <= Hangs;
        endrule

        
        // Interface
        method Bool done() = dut.done() || state_r == Hangs;
        method State state() = state_r._read();
        method Bit#(XLEN) return_value() = dut.retval();
        method Action go();
        endmethod
        method Bit#(32) return_value_exp() = exp_return_value;
        method String test_name() = test_name;
        method UInt#(XLEN) count() = count_r._read();


        `ifdef EVA_BR
            method UInt#(XLEN) correct_pred_j = dut.correct_pred_j;
            method UInt#(XLEN) wrong_pred_j = dut.wrong_pred_j;
            method UInt#(XLEN) correct_pred_br = dut.correct_pred_br;
            method UInt#(XLEN) wrong_pred_br = dut.wrong_pred_br;
        `endif
    endmodule

endpackage
