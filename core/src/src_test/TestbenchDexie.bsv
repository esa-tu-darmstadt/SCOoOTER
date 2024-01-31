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
        // `max_ticks

        //// DUT ////
        let dut <- mkWrapDexieAndScoooter();


        //// DUT CONNECTIONS ////
        // Connect to s_axi_ctrl
        AXI4_Lite_Master_Wr#(16, 32) m_axi_dexie_ctrl_wr <- mkAXI4_Lite_Master_Wr(1);
        AXI4_Lite_Master_Rd#(16, 32) m_axi_dexie_ctrl_rd <- mkAXI4_Lite_Master_Rd(1);

        mkConnection(dut.s_axi_ctrl.s_wr, m_axi_dexie_ctrl_wr.fab);
        mkConnection(dut.s_axi_ctrl.s_rd, m_axi_dexie_ctrl_rd.fab);

        // Instantiate AXI Master
        AXI4_Master_Wr#(XLEN, XLEN, 0, 0) m_axi_dexie <- mkAXI4_Master_Wr(0, 0, 0, False);
        mkConnection(dut.s_axi_bram, m_axi_dexie.fab);

        // AXI FIFO
        FIFO#(Tuple2#(Bit#(32), Bit#(32))) send_request_fifo <- mkPipelineFIFO();


        //// PATH CONFIGURATIONS ////
        function String convertIntToFile(Int#(8) i);
            // String path2Binary = "/scratch/cs_local/scoooter_dexie/dexie/binaries/en_mix1/" + "/bin/";
            String path2DexConfig = "/scratch/cs_local/scoooter_dexie/dexie/binaries/en_switch/" + "/dexie_static_good2/dexie_config/";

            return (
            case (i)
                0: ("/scratch/cs_local/scoooter_dexie/dexie/build_binaries/en_mix_simple/en_mix_simple_good.bin");
                //0: (path2Binary + "/" + "`cpu_file");
                // 0: (path2Binary + "/" + "en_mix1_good");
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

        //// ADDRESSING OFFSETS ////
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
        
        MIMO#(1, 4, 8, Bit#(8)) read_data_mimo <- mkMIMO(defaultValue);

        // Reg#(Vector#(9, Bool)) openedVec <- mkReg(unpack(0)); 
        // Reg#(Vector#(9, Bool)) readDoneVec <- mkReg(unpack(0));

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

        rule showReadDone(readDoneVec[0] && readDoneVec[1] && readDoneVec[2] && readDoneVec[3] && readDoneVec[4] && readDoneVec[5] && readDoneVec[6] && readDoneVec[7] && readDoneVec[8] && !doneReadingFiles);
            $display("Testbench: Read done.");
            doneReadingFiles <= True;
        endrule

        // We are finished reading & AXI cannot deque anymore, as we have sent all data -> nextFile
        rule sendDoneContinueWithNextFile (done && !read_data_mimo.deqReadyN(4));
            $display("Testbench: Next file. %d", i+1);
            done <= False;
            i <= i+1;
        endrule

        rule doneSending(doneReadingFiles && !done && !doneSendingFiles); // !done implies sending is finished
            $display("Testbench: Done sending files.");
            doneSendingFiles <= True;
        endrule
 
        Reg#(Bit#(32)) wordCtr <- mkReg(0);

        // get 4 bytes from mimo per access
        rule writeToAXI (read_data_mimo.deqReadyN(4));
            read_data_mimo.deq(4);
            Vector#(4, Bit#(8)) sendDataVec = read_data_mimo.first();
            Bit#(32) sendData = unpack(pack(sendDataVec));
            Bit#(32) address = get_base_address_func(i) + wordCtr*4;
            $display("Sending AXI %d addr: %h data: %h", i, address, sendData);
            send_request_fifo.enq(tuple2(address, sendData));
            wordCtr <= wordCtr + 1;
        endrule

        (* descending_urgency="readFile, sendDoneContinueWithNextFile, openFile, writeToAXI, startDexie" *)
        rule startDexie (doneSendingFiles && !startedDut);
            $display("Testbench: Starting dexie");
            send_request_fifo.enq(tuple2('h90000000, ?));
            startedDut <= True;
        endrule

        rule sendAXI;
            let req = send_request_fifo.first();
            send_request_fifo.deq();
            $display("Testbench: Sending AXI bram mem write address %h, data %h", tpl_1(req), tpl_2(req));

            let writeRequest = AXI4_Write_Rq_Addr {
                id: 0,
                addr: tpl_1(req),
                burst_length: 0,
                burst_size: bitsToBurstSize(valueOf(32)),
                burst_type: defaultValue,
                lock: defaultValue,
                cache: defaultValue,
                prot: defaultValue,
                qos: 0,
                region: 0,
                user: 0
            };
            m_axi_dexie.request_addr.put(writeRequest);

            let dataRequest = AXI4_Write_Rq_Data {
                data: tpl_2(req),
                strb: unpack(-1),
                last: True,
                user: 0
            };
            m_axi_dexie.request_data.put(dataRequest);
        endrule
    endmodule
endpackage
