package TestbenchProgram;
    import StmtFSM :: *;
    import Dave :: *;
    import Interfaces :: *;
    import Types :: *;
    import BlueAXI :: *;
    import Connectable :: *;
    import GetPut :: *;
    import BRAM :: *;
    import DefaultValue::*;
    import FIFO::*;
    import SpecialFIFOs::*;
    import Vector::*;

    // RVController emulation defines
    typedef 'h11000010 RV_CONTROLLER_RETURN_ADDRESS;
    typedef 'h11004000 RV_CONTROLLER_INTERRUPT_ADDRESS;
    typedef 'h11008000 RV_CONTROLLER_PRINT_ADDRESS;

    // Exit codes of the simulation
    typedef enum {
        Finished,
        Hangs,
        None
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
        Div#(BRAMSIZE, 4, bram_word_num_t),
        Log#(NUM_CPU, cpu_idx_t),
        Add#(cpu_idx_t, 1, cpu_and_amo_idx_t)
    );

        // status flags
        Reg#(Bool) done_r <- mkReg(False);
        Reg#(Bool) start_r <- mkReg(False);
        Reg#(State) state_r <- mkReg(None);
        // holds RVController return value
        Reg#(Bit#(XLEN)) return_r <- mkRegU();
        // counts erxecution ticks for cutoff and banchmarking
        Reg#(UInt#(XLEN)) count_r <- mkReg(0);


        let dut <- mkDave();

        `ifdef DEXIE
            rule show_dexie;
                for (Integer i = 0; i < valueOf(NUM_CPU); i=i+1) begin
                    if (isValid(dut.dexie[0].regw[i])) $display("REG: ", fshow(dut.dexie[0].regw[i]));
                    if (isValid(dut.dexie[0].cf[i]  )) $display(" CF: ", fshow(dut.dexie[0].cf[i]));
                end
                if (isValid(dut.dexie[0].memw  )) $display("MEM: ", fshow(dut.dexie[0].memw));
            endrule
            
            Reg#(Bool) stall_lol <- mkReg(False);
            rule set_dexie_stalls;
                dut.dexie[0].stall_signals(stall_lol, False);
                stall_lol <= !stall_lol;
            endrule
        `endif

        rule interrupt;
            dut.ext_int(count_r%'h3000 == 0 && count_r%'h6000 != 0 && count_r%'h8000 != 0 ? unpack({1'b1, 0}): unpack(0));
            dut.timer_int(count_r%'h6000 == 0 && count_r%'h8000 != 0 ? unpack({1'b1, 0}): unpack(0));
            dut.sw_int(count_r%'h8000 == 0 ? unpack({1'b1, 0}): unpack(0));
        endrule

        // INSTRUCTION MEMORY
        AXI4_Slave_Rd#(XLEN, ifuwidth, cpu_idx_t, 0) iram_axi <- mkAXI4_Slave_Rd(0, 0);
        mkConnection(iram_axi.fab ,dut.imem_axi);

        // create a fitting BRAM
        BRAM_Configure cfg_i = defaultValue;
        cfg_i.allowWriteResponseBypass = True;
        cfg_i.memorySize = valueOf(bram_word_num_t);
        cfg_i.loadFormat = tagged Hex imem_file;
        cfg_i.latency = 1;
        BRAM1Port#(Bit#(XLEN), Bit#(ifuwidth)) ibram <- mkBRAM1Server(cfg_i);

        FIFO#(Bit#(cpu_idx_t)) inflight_ids_inst <- mkSizedFIFO(16);

        // handle read requests
        rule ifuread if (start_r && !done_r && count_r <= fromInteger(max_ticks));
    		let r <- iram_axi.request.get();
            // the address must be converted to a word-address
            ibram.portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: (r.addr>>2)/fromInteger(valueOf(IFUINST)),
                datain: ?
            });
            inflight_ids_inst.enq(r.id);
  	    endrule

        // pass BRAM response to DUT via AXI
        rule ifuresp;
            let r <- ibram.portA.response.get();
            inflight_ids_inst.deq();
            iram_axi.response.put(AXI4_Read_Rs {data: r, id: inflight_ids_inst.first(), resp: OKAY, last: True, user: 0});
        endrule

        // DATA MEMORY
        AXI4_Slave_Wr#(XLEN, XLEN, cpu_and_amo_idx_t, 0) dram_axi_w <- mkAXI4_Slave_Wr(0, 0, 0);
        AXI4_Slave_Rd#(XLEN, XLEN, cpu_and_amo_idx_t, 0) dram_axi_r <- mkAXI4_Slave_Rd(0, 0);
        mkConnection(dram_axi_w.fab ,dut.dmem_axi_w);
        mkConnection(dram_axi_r.fab ,dut.dmem_axi_r);

        // create BRAM
        BRAM_Configure cfg_d = defaultValue;
        cfg_d.allowWriteResponseBypass = False;
        cfg_d.memorySize = valueOf(bram_word_num_t);
        cfg_d.loadFormat = tagged Hex dmem_file;
        cfg_d.latency = 1;

        BRAM2PortBE#(Bit#(XLEN), Bit#(XLEN), 4) dbram <- mkBRAM2ServerBE(cfg_d);

        // Buffer for write address prior to data arrival
        FIFO#(AXI4_Write_Rq_Addr#(XLEN, cpu_and_amo_idx_t, 0)) w_request <- mkSizedFIFO(16);

        FIFO#(Bit#(cpu_and_amo_idx_t)) w_id <- mkSizedFIFO(16);
    
        // get address requests and store them
  	    rule handleWriteRequest;
        	let r <- dram_axi_w.request_addr.get();
            w_id.enq(r.id);
        	w_request.enq(r);
    	endrule

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

        // handle data requests
    	rule returnWriteValue;
        	let r <- dram_axi_w.request_data.get();
            let addr = w_request.first().addr; w_request.deq();
            let data = r.data;
            
            // request we will send to BRAM
            let request = BRAMRequestBE{
                            writeen: 0,
                            responseOnWrite: True,
                            address: 0,
                            datain: 0
                        };

            // update RVController and dummy-read BRAM or access BRAM if in data range
            case (addr)
                fromInteger(valueOf(RV_CONTROLLER_INTERRUPT_ADDRESS)):
                    begin
                        // update status
                        done_r <= True;
                        state_r <= Finished; 
                    end
                fromInteger(valueOf(RV_CONTROLLER_RETURN_ADDRESS)):
                    begin
                        // store return value
                        return_r <= data;
                    end
                fromInteger(valueOf(RV_CONTROLLER_PRINT_ADDRESS)):
                    begin
                        $write("%c", data[7:0]);
                    end
                `ifdef RVFI
                    `TOHOST:
                        $finish();
                `endif
                default:
                    if(addr < fromInteger(2*valueOf(BRAMSIZE)) && addr >= fromInteger(valueOf(BRAMSIZE)))
                    begin
                        request.writeen = r.strb;
                        request.address = ((addr-fromInteger(valueOf(BRAMSIZE)))>>2);
                        request.datain = data;
                    end  
            endcase
            // send request
            dbram.portA.request.put(request);
    	endrule

        // get BRAM response and just notify AXI that request was successful
        rule data_resp;
            w_id.deq();
            dram_axi_w.response.put(AXI4_Write_Rs {id: w_id.first(), resp: OKAY, user:0});
            let r <- dbram.portA.response.get();
        endrule

        FIFO#(Bit#(cpu_and_amo_idx_t)) r_id <- mkPipelineFIFO();

        // read data
        rule dataread;
    		let r <- dram_axi_r.request.get();
            r_id.enq(r.id);

            // if in DRAM range, send sensible request
            if(r.addr < fromInteger(2*valueOf(BRAMSIZE)) && r.addr >= fromInteger(valueOf(BRAMSIZE)))
                dbram.portB.request.put(BRAMRequestBE{
                    writeen: 0,
                    responseOnWrite: True,
                    address: ((r.addr-fromInteger(valueOf(BRAMSIZE)))>>2),
                    datain: ?
                });
            // if out of range, send dummy
            else dbram.portB.request.put(BRAMRequestBE{ writeen: 0, responseOnWrite: True, address: 0, datain: ?});
  	    endrule

        // forward reply via AXI
        rule dataresp;
            let r <- dbram.portB.response.get();
            r_id.deq();
            dram_axi_r.response.put(AXI4_Read_Rs {data: r, id: r_id.first(), resp: OKAY, last: True, user: 0});
        endrule

        // HOUSEKEEPING

        // increment counter
        rule increment_count if (start_r && count_r <= fromInteger(max_ticks));
            count_r <= count_r + 1;
        endrule

        // stop CPU if counter overflows
        rule cutoff if(count_r > fromInteger(max_ticks));
            done_r <= True;
            state_r <= Hangs;
        endrule

        
        // Interface
        method Bool done() = done_r._read();
        method State state() = state_r._read();
        method Bit#(XLEN) return_value() = return_r._read();
        method Action go();
            start_r <= True;
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
