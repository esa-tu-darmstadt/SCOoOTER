package SoC_Mem;

import SoC_Config::*;
import Config::*;
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

interface MemMapIfc#(numeric type words_per_line);
        interface BRAM1PortBE#(Bit#(XLEN), Bit#(TMul#(words_per_line, XLEN)), TMul#(words_per_line, 4)) access;


        // SPI signals
        (*always_ready, always_enabled*)
        method Bit#(1) spi_clk;
        (*always_ready, always_enabled*)
        method Bit#(1) spi_mosi;
        (*always_ready, always_enabled*)
        method Action spi_miso(Bit#(1) i);
        (*always_ready, always_enabled*)
        method Bool spi_cs;


        // DMEM reg out
        interface Reg#(Bit#(32)) spi_div;
        interface Reg#(Bit#(32)) gpio_w;
        interface Reg#(Bit#(32)) gpio_r;

        // SPI clk div
        method Action spi_clk_div(Bit#(32) c_in);

        // vex_irq
        (*always_ready, always_enabled*)
        method Bool irq_vex();
        // vex_irq
        (*always_ready, always_enabled*)
        method Bool irq_scoooter_timer();

        (*always_ready, always_enabled*)
        method Action fs_disable_sram(Bool in);
    endinterface

    // DMEM BRAM controller
    module mkMEMMap#(Bool dmem) (MemMapIfc#(words_per_line)) provisos (
        Div#(SIZE_DMEM, 4, bram_word_num_dmem_t),
        Log#(macro_size_word_t, macro_addr_w_t),
        Mul#(macro_size_word_t, 4, MACRO_SIZE),
        Log#(words_per_line, bit_shift_addr),
        Mul#(words_per_line, XLEN, bus_width),
        Mul#(words_per_line, 4, ena_width),
        Add#(a__, 32, bus_width)
    );
        `ifdef EFSRAM
            Vector#(words_per_line, OpenRAMIfc#(0, 0, 1, 10, 32, 4)) brams <- replicateM(mkEFSRAM(True));
        `else
            BRAM_Configure cfg_i = defaultValue;
            cfg_i.allowWriteResponseBypass = False;
            cfg_i.latency = 2;
            Vector#(words_per_line, BRAM1PortBE#(Bit#(macro_addr_w_t), Bit#(XLEN), 4)) brams_i <- replicateM(mkBRAM1ServerBE(cfg_i));
            Vector#(words_per_line, OpenRAMIfc#(0, 0, 1, macro_addr_w_t, 32, 4)) brams <- mapM(mkOpenRamBRAMByteEnSP, brams_i)
        `endif

        FIFO#(Bit#(bus_width)) response_out_f <- mkPipelineFIFO();
        PulseWire inhibit_b <- mkPulseWire();
        FIFO#(Bool) rq_type <- mkSizedFIFO(1);
        
        rule get_sram_response if (rq_type.first());
            rq_type.deq();

            Vector#(words_per_line, Bit#(XLEN)) rd_data;

            for(Integer i = 0; i < valueOf(words_per_line); i=i+1) begin
                let r <- brams[i].rw[0].response();
                rd_data[i] = r;
            end

            response_out_f.enq(truncate(pack(rd_data)));
        endrule

        Reg#(Bit#(bus_width)) resp_rd <- mkRegU;
        rule get_sram_w_response if (!rq_type.first());
            rq_type.deq();
            response_out_f.enq(resp_rd);
        endrule

        // STATE REGISTERS
        // spi settings
        // gpios
        Reg#(Bit#(32)) gpio_w_r <- mkReg(0);
        Reg#(Bit#(32)) gpio_r_r <- mkReg(0);
        Reg#(Bit#(32)) gpio_r_r_2 <- mkReg(0); // incoupling of data
        Reg#(Bool) irq_vex_r <- mkReg(False);
        PulseWire irq_vex_w <- mkPulseWire();
        rule fwd_irq_vex; irq_vex_r <= irq_vex_w; endrule
        rule fwd_gpio; gpio_r_r_2 <= gpio_r_r; endrule

        `ifdef CLINT
            Vector#(2, Reg#(Bit#(32))) mtime <- replicateM(mkReg(0));
            Vector#(2, Reg#(Bit#(32))) mtimecmp <- replicateM(mkReg('hffffffff));
            //register map
            let register_map_bus = Vector::append(mtime, mtimecmp);

            // scheduling, preempt increment method if a write is in progreess
            PulseWire write_or_increment <- mkPulseWire();

            // increment mtime
            rule increment if (!write_or_increment);
                // build 64 bit word
                let new_val = {mtime[1], mtime[0]} + 1;
                // cut into 32 bit slices
                mtime[1] <= truncateLSB(new_val);
                mtime[0] <= truncate(new_val);
            endrule
        `endif

        // universal map for IMEM and DMEM
        // returns true if request handled
        function ActionValue#(Bool) handle_request_universal(BRAMRequestBE#(Bit#(XLEN), Bit#(bus_width), ena_width) r);
            actionvalue
                Bool ret = True;
                if (decodeAddressRange(r.address << 2, 0, fromInteger(valueOf(MACRO_SIZE)))) begin // directly after SPI memory
                    rq_type.enq(r.writeen == 0);

                    Vector#(words_per_line, Bit#(XLEN)) rd_data = unpack(r.datain);
                    Vector#(words_per_line, Bit#(4))    rd_ena  = unpack(r.writeen);

                    for(Integer i = 0; i < valueOf(words_per_line); i=i+1)
                        brams[i].rw[0].request(truncate(r.address>>valueOf(bit_shift_addr)), extend(rd_data[i]), rd_ena[i], r.writeen!=0);
                end

                // Signal unhandled request
                else begin
                    ret = False;
                end

                return ret;
            endactionvalue
        endfunction

        function Action handle_request_dmem(BRAMRequestBE#(Bit#(XLEN), Bit#(bus_width), ena_width) r);
            action
                // universal map
                Bool handled <- handle_request_universal(r);

                // Control registers and error handling
                if (!handled) begin

                    Bit#(32) dmem_addr = (r.address << 2) + fromInteger(valueOf(BASE_DMEM));
                    if (dmem_addr == 32'h11004000) $finish();

                    `ifdef CLINT
                        if (dmem_addr >= 'h40000000 && dmem_addr < 'h40000010) begin
                            Bit#(2) idx = truncate(r.address);
                            resp_rd <= register_map_bus[idx];
                            Bit#(32) current = register_map_bus[idx];
                            Bit#(32) update = r.datain;
                            for (Integer i = 0; i < 4; i = i+1) begin
                                Bit#(8) upd_slice = update[7+8*i:8*i];
                                if (r.writeen[i] == 1) current[7+8*i:8*i] = upd_slice;
                            end
                            register_map_bus[idx] <= current;
                            if(idx <2) write_or_increment.send();
                        end
                        else
                    `endif
                    case (dmem_addr)
                        'h80000018: begin // Print
                            resp_rd <= 0;
                            $write("%c", r.datain[7:0]);
                        end
                        default: begin
                            resp_rd <= 0; // to trigger invalidinst
                            $display("D: ACCESS FAILURE: UNKNOWN ADDRESS %h %h %h", dmem_addr, r.datain, r.writeen);
                        end
                    endcase

                    rq_type.enq(False);
                end
            endaction
        endfunction

        function Action handle_request_imem(BRAMRequestBE#(Bit#(XLEN), Bit#(bus_width), ena_width) r);
            action
                Bool handled = True;

                // universal map
                handled <- handle_request_universal(r);

                // Error handling
                if (!handled) begin
                    resp_rd <= 0;
                    $display("D: ACCESS FAILURE: UNKNOWN ADDRESS ", fshow(r.address << 2), " ", fshow(r.datain), " ", fshow(r.writeen));
                    rq_type.enq(False);
                end
            endaction
        endfunction

        interface BRAM1PortBE access;
            interface BRAMServerBE portA;

                interface Put request;
                    method Action put(BRAMRequestBE#(Bit#(XLEN), Bit#(bus_width), ena_width) r);
                        if (dmem) handle_request_dmem(r);
                        else      handle_request_imem(r);
                    endmethod
                endinterface

                interface Get response;
                    method ActionValue#(Bit#(bus_width)) get();
                        response_out_f.deq();
                        return response_out_f.first();
                    endmethod
                endinterface

            endinterface

        endinterface

        `ifdef SPI_MEMORY
            interface spi_clk = extmem.spi_clk;
            interface spi_mosi = extmem.spi_mosi;
            interface spi_miso = extmem.spi_miso;
            interface spi_cs = extmem.spi_cs;


            // regs
            interface gpio_w = gpio_w_r;
            interface gpio_r = gpio_r_r;

            method Action spi_clk_div(Bit#(32) c_in) = extmem.set_clkdiv(c_in);

            method Action fs_disable_sram(Bool in) = disable_sram._write(in);
        `endif

        `ifdef CARAVEL_IRQ
            interface irq_vex = irq_vex_r._read();
        `endif

        `ifdef CLINT
            method Bool irq_scoooter_timer();
                let mtime_64b = {mtime[1], mtime[0]}; // build mtime 64 bit word
                return (mtime_64b >= {mtimecmp[1], mtimecmp[0]});
            endmethod
        `endif

    endmodule

endpackage