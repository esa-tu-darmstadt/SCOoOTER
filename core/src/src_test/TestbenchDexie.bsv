package TestbenchDexie;
    import Interfaces :: *;
    import Types :: *;
    import BlueAXI :: *;
    import Connectable :: *;
    import GetPut :: *;
    import DefaultValue::*;
    import FIFO::*;
    import SpecialFIFOs::*;
    import Vector::*;
    import WrapDexieAndScoooter::*;
    import MIMO :: *;

    // simulates the periphery of the core
    module mkTestbenchDexie(Empty);
        // Environment variables
        // `cpu_file
        // `dexie_conf_path

        // Instantiate DUT
        let dut <- mkWrapDexieAndScoooter();

        /*
        * DUT Connections
        */
        // Instantiate AXI Lite Master and connect it to S_AXI_CTRL
        AXI4_Lite_Master_Wr#(16, 32) m_axi_dexie_ctrl_wr <- mkAXI4_Lite_Master_Wr(1);
        AXI4_Lite_Master_Rd#(16, 32) m_axi_dexie_ctrl_rd <- mkAXI4_Lite_Master_Rd(1);
        mkConnection(dut.s_axi_ctrl_wr, m_axi_dexie_ctrl_wr.fab);
        mkConnection(dut.s_axi_ctrl_rd, m_axi_dexie_ctrl_rd.fab);

        // Instantiate AXI Lite Master and connect it to S_AXI_BRAM
        AXI4_Lite_Master_Wr#(32, 32) m_axi_dexie_bram_wr <- mkAXI4_Lite_Master_Wr(1);
        AXI4_Lite_Master_Rd#(32, 32) m_axi_dexie_bram_rd <- mkAXI4_Lite_Master_Rd(1);
        mkConnection(dut.s_axi_bram_wr, m_axi_dexie_bram_wr.fab);
        mkConnection(dut.s_axi_bram_rd, m_axi_dexie_bram_rd.fab);

        /*
        * PATH CONFIGURATIONS
        */
        function String convertIntToFile(Int#(8) i);
            // Example: /scratch/cs_local/scoooter_dexie/dexie/build_binaries/en_if/dexie_static_good1/
            String path2DexConfig = `dexie_conf_path;
            // Example: /scratch/cs_local/scoooter_dexie/dexie/build_binaries/en_if/en_if_good.bin
            String path2Binary = (path2DexConfig + "/../../" + `cpu_file);
            return (
                case (i)
                    0: path2Binary;
                    1: (path2DexConfig + "/" + "1_fm.bin");
                    2: (path2DexConfig + "/" + "2_ttpt.bin");
                    3: (path2DexConfig + "/" + "3_tt.bin");
                    4: (path2DexConfig + "/" + "4_ht.bin");
                    5: (path2DexConfig + "/" + "5_fpt.bin");
                    6: (path2DexConfig + "/" + "6_flt.bin");
                    7: (path2DexConfig + "/" + "7_lct.bin");
                    8: (path2DexConfig + "/" + "8_itt.bin");
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
                0: ('h00000000);
                1: ('h10000000);
                2: ('h20000000);
                3: ('h30000000);
                4: ('h40000000);
                5: ('h50000000);
                6: ('h60000000);
                7: ('h70000000);
                8: ('h80000000);
            endcase;
        endfunction
        
        /*
        * File Handling
        */
        MIMO#(1, 4, 8, Bit#(8)) read_data_mimo <- mkMIMO(defaultValue);
        Vector#(9, Reg#(Bool)) openedVec <- replicateM(mkReg(False));
        Vector#(9, Reg#(Bool)) readDoneVec <- replicateM(mkReg(False));
        Reg#(Bool) done <- mkReg(False);
        Reg#(Vector#(9, File)) file_descriptors_vec <- mkReg(?);
        Reg#(Int#(8)) i <- mkReg(0); // Read file index
        Reg#(Int#(32)) readByteCtr <- mkReg(0);

        rule openFile( !openedVec[i] && !readDoneVec[i] );
            String readFile = convertIntToFile(i);
            let file_descr <- $fopen(readFile, "rb" );
            file_descriptors_vec[i] <= file_descr;
            openedVec[i] <= True;
            $display("Testbench: Opening file %s", readFile);
        endrule

        rule readFile(openedVec[i] && !readDoneVec[i]);
            int content <- $fgetc( file_descriptors_vec[i] );
            // $display("Testbench: Reading file %d", i);
            if ( content != -1 ) begin
                Bit#(8) read_byte = truncate( pack(content) );
                read_data_mimo.enq(1, unpack(pack(read_byte))); // Markus: cast zum vector besser?
                readByteCtr <= readByteCtr + 1;
            end else begin // EOF
                $display( "Testbench: EOF after %d bytes; file %d %s", readByteCtr, i, convertIntToFile(i));
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

        rule showReadDone(readDoneVec[0] && readDoneVec[1] && readDoneVec[2] && readDoneVec[3] && readDoneVec[4] && readDoneVec[5] && readDoneVec[6] && readDoneVec[7] && readDoneVec[8] && !doneReadingFiles);
            $display("Testbench: Read done.");
            doneReadingFiles <= True;
        endrule

        // We are finished reading & AXI cannot deque anymore, as we have sent all data -> nextFile
        rule sendDoneContinueWithNextFile (done && !read_data_mimo.deqReadyN(4));
            $display("Testbench: Sensing next file. %d", i+1);
            done <= False;
            i <= i+1;
            wordCtr <= 0;
        endrule

        rule doneSending(doneReadingFiles && !done && !doneSendingFiles); // !done implies sending is finished
            $display("Testbench: Done sending files.");
            doneSendingFiles <= True;
        endrule


        /*
        * AXI BRAM Sending Data
        */
        FIFO#(Tuple2#(Bit#(32), Bit#(32))) send_request_fifo <- mkPipelineFIFO();

        rule writeToAXI (read_data_mimo.deqReadyN(4));
                read_data_mimo.deq(4); // get 4 bytes from mimo per access
                Vector#(4, Bit#(8)) sendDataVec = read_data_mimo.first();
                Bit#(32) sendData = unpack(pack(sendDataVec));
                Bit#(32) address = get_base_address_func(i) + wordCtr*4;
                $display("Sending AXI %d addr: %h data: %h", i, address, sendData);
                send_request_fifo.enq(tuple2(address, sendData));
                wordCtr <= wordCtr + 1;
        endrule

        rule sendAXI;
            let req = send_request_fifo.first();
            send_request_fifo.deq();
            $display("Testbench: Sending AXI bram mem write address %h, data %h", tpl_1(req), tpl_2(req));
            let writeRequest = AXI4_Lite_Write_Rq_Pkg {
                addr: tpl_1(req),
                data: tpl_2(req),
                strb: unpack(-1),
                prot: unpack(0)
            };
            m_axi_dexie_bram_wr.request.put(writeRequest);
        endrule

        rule discardAxiResponse;
            $display("Testbench: Received AXI response");
            let resp <- m_axi_dexie_bram_wr.response.get();
        endrule

        /*
        * Starting DExIE
        */
        Reg#(Int#(8)) startCtr <- mkReg(0);

        (* descending_urgency="readFile, sendDoneContinueWithNextFile, openFile, writeToAXI, startDexie" *)
        rule setDexieReady (doneSendingFiles && !startedDut);
            $display("Testbench: Starting dexie");
            send_request_fifo.enq(tuple2('h90000000, ?));
            startedDut <= True;
            startCtr <= 1;
        endrule

        // TODO: Find minimal startup delay and investigate potential hang
        rule incrementStartCtr (startedDut && startCtr < 51);
            $display("Start ctr: %d", startCtr);
            startCtr <= startCtr + 1;
        endrule

        rule startDexie (startedDut && startCtr==50);
            $display("Testbench: Starting dexie");
            // Just setting the start bit (optional: 0x4 InterruptEnable and 0x8)
            let writeRequest = AXI4_Lite_Write_Rq_Pkg {
                    addr: 0,
                    data: 1,
                    strb: unpack(-1),
                    prot: unpack(0)
                };
            m_axi_dexie_ctrl_wr.request.put(writeRequest);
        endrule

        /*
        * Handling DExIE Interrupt and stopping Simulation
        */

        Reg#(Bool) receivedInterrupt <- mkReg(False);

        rule getDexieInterrupt(startedDut && dut.irq() && !receivedInterrupt);
            $display("Received DExIE Interrupt.");
            receivedInterrupt <= True;
            let readRequest = AXI4_Lite_Read_Rq_Pkg{
                addr: 'h30,
                prot: unpack(0)
            };
            m_axi_dexie_ctrl_rd.request.put(readRequest);
        endrule

        rule readDexieResponseCodeAndFinishSimulation(receivedInterrupt);
            let res <- m_axi_dexie_ctrl_rd.response.get();
            $display("Received response %d", res.data);
            $finish(unpack(extend(pack(res.data==0))));
        endrule

    endmodule
endpackage
