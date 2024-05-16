package RamSim;

import ClientServer::*;
import GetPut::*;
import Vector::*;
import FIFO::*;
import RegFile::*;

typedef 32 XLEN;

interface SPI;
    (*always_ready, always_enabled*)
    method Action spi_clk(Bit#(1) in);
    (*always_ready, always_enabled*)
    method Action spi_mosi(Bit#(1) in);
    (*always_ready, always_enabled*)
    method Bit#(1) spi_miso();
    (*always_ready, always_enabled*)
    method Action spi_cs(Bool in);
endinterface

(*synthesize*)
module mkRAM(SPI);

    // storage cells
    //Vector#(524288, Reg#(Bit#(8))) array <- replicateM(mkRegU);
    RegFile#(Bit#(24), Bit#(8)) regs <- mkRegFileFull();

    // iface wires
    Wire#(Bit#(1)) mosi <- mkBypassWire();
    Wire#(Bit#(1)) sck <- mkBypassWire();
    Wire#(Bool) cs <- mkBypassWire();


    Reg#(Bit#(8)) command <- mkRegU;
    Reg#(Bit#(8)) command_ctr <- mkReg(0);


    Reg#(Bit#(24)) addr <- mkRegU;
    Reg#(Bit#(8)) addr_ctr <- mkReg(0);

    Reg#(Bit#(8)) wrdata <- mkRegU;
    Reg#(Bit#(8)) wrdata_ctr <- mkReg(0);

    Reg#(Bit#(8)) rdata_ctr <- mkReg(0);

    Reg#(Bit#(1)) miso <- mkRegU;

    // 0: wait for cmd
    // 1: read addr
    // 2: broadcast data / read data
    // 3: done
    Reg#(Bit#(8)) state <- mkRegU;

    Reg#(Bool) cs_prv <- mkReg(False);
    rule str_cs; cs_prv <= cs; endrule

    Reg#(Bit#(1)) clk_prv <- mkRegU;
    rule str_clk; clk_prv <= sck; endrule
    
    rule cs_valid if (!cs_prv && cs);

        state <= 0;
        command_ctr <= 0;
        addr_ctr <= 0;
        wrdata_ctr <= 0;
        rdata_ctr <= 0;

    endrule

    // if cmd unknown and rising flag
    rule get_opc if (state == 0 && command_ctr < 8 && clk_prv == 0 && sck == 1 && cs);

        command <= truncate({command, mosi});
        command_ctr <= command_ctr + 1;

    endrule

    rule advance_opc if (command_ctr == 8 && cs && state == 0);

        case (command)
            8'b00000110: begin
                //$display("write enabled");
                state <= 3;
            end

            8'b00000010: begin
                state <= 1;
            end

            8'b00000011: begin
                //$display("got read");
                state <= 1;
            end

        endcase
    endrule



    rule get_addr if (state == 1 && addr_ctr < 24 && clk_prv == 0 && sck == 1 && cs);

        addr <= truncate({addr, mosi});
        addr_ctr <= addr_ctr + 1;
    endrule

    rule advance_addr if (addr_ctr == 24 && cs && state == 1);
        state <= 2;
        //$display("addr", fshow(addr));
    endrule


    rule get_wr_data if (command == 'b10 && state == 2 && wrdata_ctr < 8 && clk_prv == 0 && sck == 1 && cs);
        wrdata_ctr <= wrdata_ctr + 1;
        wrdata <= truncate({wrdata, mosi});
    endrule

    rule write_wr_data if (command == 'b10 && state == 2 && wrdata_ctr == 8 && cs);
        regs.upd(addr, wrdata);
        //$display("writing ", fshow(wrdata), " to ", fshow (addr));
        state <= 3;
    endrule


    rule send_read_data if (command == 'b11 && state == 2 && rdata_ctr < 32 && clk_prv == 1 && sck == 0 && cs);
        rdata_ctr <= rdata_ctr + 1;
        let current_byte = regs.sub(addr + extend(rdata_ctr)/8);
        Bit#(3) addr_bit = 7-truncate(rdata_ctr);

        Bit#(1) current_bit = current_byte[addr_bit];
        miso <= current_bit;
    endrule


    method Action spi_cs(Bool c) = cs._write(!c);
    interface spi_mosi = mosi._write;
    interface spi_clk = sck._write;
    interface spi_miso = miso._read;

endmodule

endpackage
