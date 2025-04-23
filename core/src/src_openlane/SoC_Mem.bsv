package SoC_Mem;

import SoC_Config::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import SPICore::*;
import MemoryDecoder::*;
import OpenRAMIfc::*;
import GetPut::*;
import ClientServer::*;
import BRAM::*;
import OpenRAMIfc::*;

import BUtils::*;
import EFSRAM::*;
import BRAMCore::*;
import OpenRAMIfc::*;
import WrapBRAMAsOpenRAM::*;
import Config::*;

/*

This module provides the IMEM and DMEM for the SoC design and adds periphery.
Currently, periphery contains a CLINT, IRQ to Caravel and GPIO pins.

*/

interface MemMapIfc;
        // shared memory interfrace from SCOoOTER and Caravel
        interface BRAM1PortBE#(Bit#(XLEN), Bit#(XLEN), 4) access;

        // GPIO input and output
        (* always_ready, always_enabled *)
        method Action gpio_in(Bit#(32) d);
        (* always_ready, always_enabled *)
        method Bit#(32) gpio_out;

        // IRQ from SCOoOTER to Caravel
        (*always_ready, always_enabled*)
        method Bool irq_vex();
        // timer IRQ to SCOoOTER
        (*always_ready, always_enabled*)
        method Bool irq_scoooter_timer();
    endinterface


    // Main memory map module
    // A parameter selects if an instance acts as IMEM or DMEM
    // For IMEM, periphery is removed
    // A limitation of this approach is the requirement for equaly-sized IMEM and DMEM
    // Since the same SRAM macro is used
    module mkMEMMap#(Bool dmem) (MemMapIfc) provisos (
        Log#(macro_size_word_t, macro_addr_w_t), // calculate address width for SRAM macros
        Mul#(macro_size_word_t, 4, MACRO_SIZE)
    );


        /*
        
        SRAM memory instantiation
        
        */


        // either instantiate an SRAM macro (Verilog simulation)
        // or a BRAM (BlueSim simulation)
        // Through BlueSRAM, both can be wrapped as the same interface
        `ifdef EFSRAM
            // other BlueSRAM macros can be used here
            // e.g. openRAM or DFFRAM
            // When changing the macro type, 
            OpenRAMIfc#(0, 0, 1, 10, 32, 4) bram <- mkEFSRAM(True);
        `else
            BRAM_Configure cfg_i = defaultValue;
            cfg_i.allowWriteResponseBypass = False;
            cfg_i.latency = 2;
            BRAM1PortBE#(Bit#(macro_addr_w_t), Bit#(XLEN), 4) bram_i <- mkBRAM1ServerBE(cfg_i);
            OpenRAMIfc#(0, 0, 1, macro_addr_w_t, 32, 4) bram <- mkOpenRamBRAMByteEnSP(bram_i);
        `endif

        /*
        
        General memory bus handling
        
        */

        // buffer responses from SRAM macro
        FIFO#(Bit#(XLEN)) response_out_f <- mkPipelineFIFO();
        // store if last read request went to SRAM or periphery
        // SRAM = True ; Periphery = False
        FIFO#(Bool) rq_type <- mkSizedFIFO(1);
        

        // Respond to the processor via memory bus
        // only reads require a response

        // forward read data via memory bus
        // get data from SRAM and send to processor
        rule get_sram_response if (rq_type.first());
            rq_type.deq();
            let r <- bram.rw[0].response();
            response_out_f.enq(truncate(r));
        endrule

        // forward read data from periphery
        // The register is used to buffer periphery response data
        Reg#(Bit#(XLEN)) resp_rd <- mkRegU;
        rule get_sram_w_response if (!rq_type.first());
            rq_type.deq();
            response_out_f.enq(resp_rd);
        endrule


        /*
        
        Periphery
        
        */


        // STATE REGISTERS (Periphery)
        // GPIOs (output - written from processor)
        Reg#(Bit#(32)) gpio_out_r <- mkReg(0);
        // GPIOs (input - read from processor)
        // Since the GPIO signals are coming from external
        // they are not aligned with our clock domain.
        // Hence, to avoid faulty astable states of our signals,
        // we must pass the signals through two sequential flipflops.
        Reg#(Bit#(32)) gpio_in_r <- mkReg(0);
        Reg#(Bit#(32)) gpio_in_r_2 <- mkReg(0);    
        //rule fwd_gpio; gpio_r_r_2 <= gpio_r_r; endrule

        // Interrupt signal to Caravel
        // Can be used to signal the end of program execution
        Reg#(Bool) irq_vex_r <- mkReg(False);


        // CLINT (system timer and interrupts)
        // Refer to the CLINT specification for more information
        // Create standard 64 bit mtime and mtimecmp registers
        Vector#(2, Reg#(Bit#(32))) mtime <- replicateM(mkReg(0));
        Vector#(2, Reg#(Bit#(32))) mtimecmp <- replicateM(mkReg('hffffffff));
        // Generate a register map which is accessed by the processor
        let register_map_bus = Vector::append(mtime, mtimecmp);

        // scheduling, preempt increment of mtime if a write is in progreess
        PulseWire write_or_increment <- mkPulseWire();

        // increment mtime
        rule increment if (!write_or_increment);
            // build 64 bit word
            let new_val = {mtime[1], mtime[0]} + 1;
            // cut into 32 bit slices
            mtime[1] <= truncateLSB(new_val);
            mtime[0] <= truncate(new_val);
        endrule


        /*
        
        Request routing
        
        */


        // universal map for IMEM and DMEM
        // returns true if request handled
        function ActionValue#(Bool) handle_request_universal(BRAMRequestBE#(Bit#(XLEN), Bit#(XLEN), 4) r);
            actionvalue
                Bool ret = True;

                // check if address is in SRAM range
                // if yes, request from SRAM
                if (decodeAddressRange(r.address << 2, 0, fromInteger(valueOf(MACRO_SIZE)))) begin
                    rq_type.enq(r.writeen == 0);
                    bram.rw[0].request(truncate(r.address), extend(r.datain), r.writeen, r.writeen!=0);
                end

                // If unhandled, return false to signify periphery address space
                else begin
                    ret = False;
                end

                return ret;
            endactionvalue
        endfunction

        // DMEM-Specific request handling
        // In addition to SRAM, connects periphery
        function Action handle_request_dmem(BRAMRequestBE#(Bit#(XLEN), Bit#(XLEN), 4) r);
            action
                // First, call the universal handler for SRAM handling
                Bool handled <- handle_request_universal(r);

                // if the SRAM handler did not handle the request, use periphery
                if (!handled) begin

                    // regenerate byte address with dmem offset
                    // as this address matches to the addresses used in program code
                    // and hence makes modifying this module simpler and less error-prone
                    Bit#(32) dmem_addr = (r.address << 2) + fromInteger(valueOf(BASE_DMEM));

                    // CLINT
                    if (dmem_addr >= 'h40000000 && dmem_addr < 'h40000010) begin
                        // access the memory map of CLINT
                        // generate the truncated word address
                        Bit#(2) idx = truncate(r.address);
                        // store the read value for possible forwarding to the processor
                        // (if the request has been a read)
                        resp_rd <= register_map_bus[idx];
                        Bit#(32) current = register_map_bus[idx];
                        Bit#(32) update = r.datain;
                        // evaluate strobe bits and write bytes
                        for (Integer i = 0; i < 4; i = i+1) begin
                            Bit#(8) upd_slice = update[7+8*i:8*i];
                            if (r.writeen[i] == 1) current[7+8*i:8*i] = upd_slice;
                        end
                        // write modified value to CLINT
                        register_map_bus[idx] <= current;
                        // if mtime has been written, do not increment the timer this cycle
                        if(idx <2) write_or_increment.send();
                    end else
                    case (dmem_addr)
                        // print text from program in simulation
                        // allows for naive debugging or progress displaying
                        'h80000018: begin
                            resp_rd <= 0;
                            $write("%c", r.datain[7:0]);
                        end
                        // GPIOs
                        // inputs
                        'h80000000: begin
                            resp_rd <= gpio_out_r;
                            if (r.writeen == 'hf) gpio_out_r <= r.datain;
                        end
                        // outputs
                        'h80000004: begin
                            resp_rd <= gpio_in_r_2;
                        end
                        // RVController emulation
                        'h11004000: begin
                            // return from test program - notify Caravel
                            irq_vex_r <= unpack(r.datain[0]);
                        end
                        'h11000010: begin
                            // return value from test program
                            // unused but checked for to avoid error prints
                        end
                        // error if the address did not match any register space
                        default: begin
                            resp_rd <= 0; // to trigger invalidinst
                            $display("D: ACCESS FAILURE: UNKNOWN ADDRESS %h %h %h", dmem_addr, r.datain, r.writeen);
                        end
                    endcase

                    // response from periphery, not SRAM
                    rq_type.enq(False);
                end
            endaction
        endfunction

        // DMEM-Specific request handling
        // Only connect SRAM
        function Action handle_request_imem(BRAMRequestBE#(Bit#(XLEN), Bit#(XLEN), 4) r);
            action
                Bool handled = True;

                // First, call the universal handler for SRAM handling
                handled <- handle_request_universal(r);

                // Print an error if memory outside of the SRAM has been accessed
                if (!handled) begin
                    resp_rd <= 0;
                    $display("D: ACCESS FAILURE: UNKNOWN ADDRESS ", fshow(r.address << 2), " ", fshow(r.datain), " ", fshow(r.writeen));
                    rq_type.enq(False);
                end
            endaction
        endfunction

        // access interface to the memory / periphery
        interface BRAM1PortBE access;
            interface BRAMServerBE portA;

                // forward requests
                interface Put request;
                    method Action put(BRAMRequestBE#(Bit#(XLEN), Bit#(XLEN), 4) r);
                        // differentiate between IMEM and DMEM
                        if (dmem) handle_request_dmem(r);
                        else      handle_request_imem(r);
                    endmethod
                endinterface

                // return responses
                interface Get response;
                    method ActionValue#(Bit#(XLEN)) get();
                        response_out_f.deq();
                        return response_out_f.first();
                    endmethod
                endinterface

            endinterface

        endinterface

        // interrupt to Caravel
        interface irq_vex = irq_vex_r._read();

        // timer interrupt from CLINT to SCOoOTER
        method Bool irq_scoooter_timer();
            let mtime_64b = {mtime[1], mtime[0]}; // build mtime 64 bit word
            return (mtime_64b >= {mtimecmp[1], mtimecmp[0]});
        endmethod

        // GPIOs
        method Action gpio_in(Bit#(32) d) = gpio_in_r._write(d);
        method Bit#(32) gpio_out = gpio_out_r;

    endmodule

endpackage