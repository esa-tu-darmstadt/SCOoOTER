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


/*

Testbench module for the AXI SoC

*/


    module mkTestSoC(Empty);

        // Instantiate DUT
        let dut <- mkSoC();

        // Tie off GPIO pins
        rule gpio;
            dut.gpio_in(dut.gpio_out());
        endrule

        /*
        * DUT Connections
        */

        // Instantiate AXI Lite Master and connect it to S_AXI_BRAM
        AXI4_Lite_Master_Wr#(32, 32) m_axi_bram_wr <- mkAXI4_Lite_Master_Wr(1);
        AXI4_Lite_Master_Rd#(32, 32) m_axi_bram_rd <- mkAXI4_Lite_Master_Rd(1);
        mkConnection(dut.s_axi_bram_wr, m_axi_bram_wr.fab);
        mkConnection(dut.s_axi_bram_rd, m_axi_bram_rd.fab);

        /*
        * Paths of the binaries to be loaded
        */
        function String convertIntToFile(Int#(2) i);
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
        function Bit#(32) get_base_address_func(Int#(2) index);
            // MSB selects memory partition
            return
            case (index)
                0:  (32'h_30_00_00_00 + ( fromInteger(valueOf(WB_OFFSET_IMEM)) << 26 ));
                1:  (32'h_30_00_00_00 + ( fromInteger(valueOf(WB_OFFSET_DMEM)) << 26 ));
            endcase;
        endfunction
        
        /*
        * File Handling
        */
        // A MIMO is used to read bytes from a file and combine them into 4-Byte Words
        MIMO#(1, 4, 8, Bit#(8)) read_data_mimo <- mkMIMO(defaultValue);

        // Tracking if a file has been opened and read
        Vector#(2, Reg#(Bool)) openedVec <- replicateM(mkReg(False));
        Vector#(2, Reg#(Bool)) readDoneVec <- replicateM(mkReg(False));

        // Flag to signify loading of current file is done
        Reg#(Bool) done <- mkReg(False);

        // Flag to signify all files were loaded
        Reg#(Bool) doneReadingFiles <- mkReg(False);

        // counter for word address generation while writing to IMEM / DMEM
        Reg#(Bit#(32)) wordCtr <- mkReg(0);

        // Storage to hold file descriptors
        Reg#(Vector#(2, File)) file_descriptors_vec <- mkReg(?);
        // Stores the index of the currently-read file
        Reg#(Int#(2)) i <- mkReg(0);
        // Counts the bytes read from a file
        Reg#(Int#(32)) readByteCtr <- mkReg(0);

        // open a file, once it should be loaded
        rule openFile( !openedVec[i] && !readDoneVec[i] );
            String readFile = convertIntToFile(i);
            let file_descr <- $fopen(readFile, "rb" );
            file_descriptors_vec[i] <= file_descr;
            openedVec[i] <= True;
        endrule

        // once opened, read bytes from the file
        rule readFile(openedVec[i] && !readDoneVec[i]);
            int content <- $fgetc( file_descriptors_vec[i] );

            // if we are still getting data...
            if ( content != -1 ) begin
                // ... place it into the MIMO and increment the read counter
                Bit#(8) read_byte = truncate( pack(content) );
                read_data_mimo.enq(1, unpack(pack(read_byte)));
                readByteCtr <= readByteCtr + 1;
            // if the file end has been reached, move to the next file
            end else begin
                readDoneVec[i] <= True;
                done <= True;
                readByteCtr <= 0;
                $fclose ( file_descriptors_vec[i] );
            end
        endrule

        // Advance to the next file
        rule sendDoneContinueWithNextFile (done && !read_data_mimo.deqReadyN(4));
            done <= False;
            i <= i+1;
            wordCtr <= 0;
        endrule


        /*
        * AXI BRAM Sending Data
        */

        // dequeue four bytes at a time and send writes to IMEM / DMEM
        rule writeToBus (read_data_mimo.deqReadyN(4));
            read_data_mimo.deq(4);
            Vector#(4, Bit#(8)) sendDataVec = read_data_mimo.first();
            Bit#(32) sendData = unpack(pack(sendDataVec));
            Bit#(32) address = get_base_address_func(i) + wordCtr*4;

            m_axi_bram_wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                addr: address,
                data: sendData,
                strb: unpack(-1),
                prot: unpack(0)
            });

            $write("."); $fflush();
            wordCtr <= wordCtr + 1;
        endrule

        // once all files were read, issue special write to start the system
        rule showReadDone(readDoneVec[0] && readDoneVec[1] && !doneReadingFiles);
            doneReadingFiles <= True;

            m_axi_bram_wr.request.put(AXI4_Lite_Write_Rq_Pkg {
                addr: ((fromInteger(valueOf(WB_OFFSET_START)) << 26)),
                data: 1,
                strb: unpack(-1),
                prot: unpack(0)
            });
        endrule

        // dequeue AXI responses
        rule discardAxiResponse;
            let resp <- m_axi_bram_wr.response.get();
        endrule

        // end simulation once SCOoOTER sets its interrupt pin
        rule endSimulation if (dut.irq_vex());
            $finish();
        endrule
        

    endmodule
endpackage
