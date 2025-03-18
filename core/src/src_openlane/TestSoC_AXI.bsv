package TestSoC_AXI;
    import BlueAXI :: *;
    import Connectable :: *;
    import GetPut :: *;
    import DefaultValue::*;
    import FIFO::*;
    import SpecialFIFOs::*;
    import Vector::*;
    import SoC_AXI::*;
    import SoC_Config::*;
    import MIMO :: *;
    import RamSim::*;

    // simulates the periphery of the core
    module mkTestSoC(Empty);
        // Environment variables
        // `cpu_file
        // `dexie_conf_path

        // Instantiate DUT
        let dut <- mkSoC();

        rule gpio;
            dut.gpio_in(0);
        endrule

        rule failsafe;
            dut.fs_dexie_disable(False);
            dut.fs_mgmt_disable(False);
            dut.fs_boot_from_SPI(False);
            dut.fs_stall_core(False);
            dut.fs_int_core(False);
        endrule

        // connect SPI mem simulation
        let dmem <- mkRAM();
        let imem <- mkRAM();
        rule connect_spi_dmem;
            dmem.spi_mosi(dut.spi_mosi_dmem);
            dmem.spi_clk(dut.spi_clk_dmem);
            dmem.spi_cs(dut.spi_cs_dmem);
            dut.spi_miso_dmem(dmem.spi_miso());

            imem.spi_mosi(dut.spi_mosi_imem);
            imem.spi_clk(dut.spi_clk_imem);
            imem.spi_cs(dut.spi_cs_imem);
            dut.spi_miso_imem(imem.spi_miso());
        endrule

        /*
        * DUT Connections
        */

        // Instantiate AXI Lite Master and connect it to S_AXI_BRAM
        AXI4_Lite_Master_Wr#(32, 32) m_axi_dexie_bram_wr <- mkAXI4_Lite_Master_Wr(1);
        AXI4_Lite_Master_Rd#(32, 32) m_axi_dexie_bram_rd <- mkAXI4_Lite_Master_Rd(1);
        mkConnection(dut.s_axi_bram_wr, m_axi_dexie_bram_wr.fab);
        mkConnection(dut.s_axi_bram_rd, m_axi_dexie_bram_rd.fab);

        /*
        * PATH CONFIGURATIONS
        */
        function String convertIntToFile(Int#(8) i);
            String path2BinaryInstr = "/scratch/ms/scoooter/tools/riscv-tests/out/32ui/bin/rv32ui-p-add.bin";
            String path2BinaryData =  "/scratch/ms/scoooter/tools/riscv-tests/out/32ui/bin/rv32ui-p-add.bin";
            return (
                case (i)
                    0: path2BinaryInstr;
                    1: path2BinaryData;
                endcase
            );
        endfunction

        /*
        * ADDRESSING OFFSETS
        */
        function Bit#(32) get_base_address_func(Int#(8) index);
            // MSB selects memory partition
            return
            case (index)
                0:  32'h_30_00_00_00 + ( wb_offset_imem << 26 );
                1:  32'h_30_00_00_00 + ( wb_offset_dmem << 26 );
            endcase;
        endfunction
        
        /*
        * File Handling
        */
        MIMO#(1, 4, 8, Bit#(8)) read_data_mimo <- mkMIMO(defaultValue);
        Vector#(11, Reg#(Bool)) openedVec <- replicateM(mkReg(False));
        Vector#(11, Reg#(Bool)) readDoneVec <- replicateM(mkReg(False));
        Reg#(Bool) done <- mkReg(False);
        Reg#(Vector#(11, File)) file_descriptors_vec <- mkReg(?);
        Reg#(Int#(8)) i <- mkReg(0); // Read file index
        Reg#(Int#(32)) readByteCtr <- mkReg(0);

        rule openFile( !openedVec[i] && !readDoneVec[i] );
            String readFile = convertIntToFile(i);
            let file_descr <- $fopen(readFile, "rb" );
            file_descriptors_vec[i] <= file_descr;
            openedVec[i] <= True;
            //feature_log($format("Opening file %s", readFile), L_Testbench);
        endrule

        rule readFile(openedVec[i] && !readDoneVec[i]);
            int content <- $fgetc( file_descriptors_vec[i] );
            if ( content != -1 ) begin
                Bit#(8) read_byte = truncate( pack(content) );
                read_data_mimo.enq(1, unpack(pack(read_byte)));
                readByteCtr <= readByteCtr + 1;
            end else begin // EOF
                //LogType logType = (readByteCtr == 0) ? L_WARNING : L_Testbench;
                //feature_log($format("EOF after %d bytes; file %d %s", readByteCtr, i, convertIntToFile(i)), logType);
                readDoneVec[i] <= True;
                done <= True;
                readByteCtr <= 0;
                $fclose ( file_descriptors_vec[i] );
            end
        endrule

        Reg#(Bool) doneReadingFiles <- mkReg(False);
        Reg#(Bool) doneSendingFiles <- mkReg(False);
        Reg#(Bool) startedDut <- mkReg(False);
        Reg#(Bit#(32)) wordCtr <- mkReg(0);

        rule showReadDone(readDoneVec[0] && readDoneVec[1] && readDoneVec[2] && readDoneVec[3] && readDoneVec[4] && readDoneVec[5] && readDoneVec[6] && readDoneVec[7] && readDoneVec[8] && readDoneVec[9] && readDoneVec[10] && !doneReadingFiles);
            //feature_log($format("Read done."), L_Testbench);
            doneReadingFiles <= True;
        endrule

        // We are finished reading & AXI cannot deque anymore, as we have sent all data -> nextFile
        rule sendDoneContinueWithNextFile (done && !read_data_mimo.deqReadyN(4));
            //feature_log($format("Sending next file."), L_Testbench);
            done <= False;
            i <= i+1;
            wordCtr <= 0;
        endrule

        rule doneSending(doneReadingFiles && !done && !doneSendingFiles); // !done implies sending is finished
            //feature_log($format("Done sending files."), L_Testbench);
            doneSendingFiles <= True;
        endrule


        /*
        * AXI BRAM Sending Data
        */
        FIFO#(Tuple2#(Bit#(32), Bit#(32))) send_request_fifo <- mkPipelineFIFO();

        rule writeToBus (read_data_mimo.deqReadyN(4));
            read_data_mimo.deq(4); // get 4 bytes from mimo per access
            Vector#(4, Bit#(8)) sendDataVec = read_data_mimo.first();
            Bit#(32) sendData = unpack(pack(sendDataVec));
            Bit#(32) address = get_base_address_func(i) + wordCtr*4;
            send_request_fifo.enq(tuple2(address, sendData));
            $write("."); $fflush();
            wordCtr <= wordCtr + 1;
        endrule

        rule sendAXI;
            let req = send_request_fifo.first();
            send_request_fifo.deq();
            //feature_log($format("Sending AXI bram mem write address %h, data %h", tpl_1(req), tpl_2(req)), L_TestbenchAXI);
            let writeRequest = AXI4_Lite_Write_Rq_Pkg {
                addr: tpl_1(req),
                data: tpl_2(req),
                strb: unpack(-1),
                prot: unpack(0)
            };
            m_axi_dexie_bram_wr.request.put(writeRequest);
        endrule

        Reg#(Bool) receivedInterrupt <- mkReg(False);
        rule discardAxiResponse(!receivedInterrupt);
            //feature_log($format("Received AXI response"), L_TestbenchAXI);
            let resp <- m_axi_dexie_bram_wr.response.get();
        endrule

        // /*
        // * Starting DExIE
        // */
        Reg#(Int#(9)) startCtr <- mkReg(0);

        (* descending_urgency="readFile, sendDoneContinueWithNextFile, openFile, writeToBus, startDexie" *)
        rule setDexieReady (doneSendingFiles && !startedDut);
            //feature_log($format("Set DExIE ready"), L_Testbench);
            send_request_fifo.enq(tuple2(get_base_address_func(11), ?));
            startedDut <= True;
            startCtr <= 1;
        endrule

        // TODO: Find minimal startup delay and investigate potential hang
        rule incrementStartCtr (startedDut && startCtr < 121);
            //feature_log($format("Incrementing startCtr"), L_Testbench);
            startCtr <= startCtr + 1;
        endrule

        rule startDexie (startedDut && startCtr==120);
            //feature_log($format("Starting DExIE"), L_Testbench);
            // Just setting the start bit (optional: 0x4 InterruptEnable and 0x8)
            send_request_fifo.enq(tuple2((wb_offset_axi_ctrl<<26), 1));
        endrule

        /*
        * Handling DExIE Interrupt and stopping Simulation
        */
        rule getDexieInterrupt(startedDut && dut.irq() && !receivedInterrupt);
            //feature_log($format("Received DExIE Interrupt."), L_Testbench);
            receivedInterrupt <= True;
            let readRequest = AXI4_Lite_Read_Rq_Pkg{
                addr: (wb_offset_axi_ctrl<<26) + 'h30,
                prot: unpack(0)
            };
            m_axi_dexie_bram_rd.request.put(readRequest);
        endrule

        rule readDexieResponseCodeAndFinishSimulation(startedDut && receivedInterrupt);
            let res <- m_axi_dexie_bram_rd.response.get();
            //feature_log($format("Received response %d", res.data), L_Testbench);
            $finish(unpack(extend(pack(res.data==0))));
        endrule

    endmodule
endpackage
