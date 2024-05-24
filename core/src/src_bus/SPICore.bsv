package SPICore;

import ClientServer::*;
import GetPut::*;
import Vector::*;
import FIFO::*;

typedef 32 XLEN;

// rd/wr interface with SPI output
interface SPICore#(numeric type idx_width);

    // request/response iface for rd/wr
    interface Server#(Tuple2#(UInt#(XLEN), Bit#(idx_width)), Tuple2#(Bit#(XLEN), Bit#(idx_width))) r;
    interface Server#(Tuple4#(UInt#(XLEN), Bit#(XLEN), Bit#(4), Bit#(idx_width)), Bit#(idx_width)) w;

    // SPI sognals
    (*always_ready, always_enabled*)
    method Bit#(1) spi_clk;
    (*always_ready, always_enabled*)
    method Bit#(1) spi_mosi;
    (*always_ready, always_enabled*)
    method Action spi_miso(Bit#(1) i);
    (*always_ready, always_enabled*)
    method Bool spi_cs;

    (*always_ready,always_enabled*)
    method Action set_clkdiv(Bit#(32) in);
endinterface


module mkSPICore(SPICore#(idx_width));

    // initial pause
    Reg#(Bit#(8)) init_r <- mkReg(255);
    rule countdown_init if (init_r > 0); init_r <= init_r-1; endrule


    // clk edges
    Wire#(Bool) rising_edge <- mkBypassWire();
    Wire#(Bool) falling_edge <- mkBypassWire();
    // clk divider
    Wire#(Bit#(32)) clk_div_in <- mkBypassWire();
    Array#(Reg#(Bit#(32))) clkdiv <- mkCReg(2, 0);
    rule clk_div;
        if (init_r == 0) begin
            if (clkdiv[0] == clk_div_in-1)
                clkdiv[0] <= 0;
            else 
                clkdiv[0] <= clkdiv[0]+1;
        end
        falling_edge <= (clkdiv[0] == 0);
        rising_edge  <= (clkdiv[0] == clk_div_in>>1);
    endrule

    

    // cmd reg (8b op + 24b addr + 32b data)
    Reg#(Bit#(172)) command_reg <- mkRegU();
    Reg#(Bit#(172)) suppress_cs_reg <- mkReg(0);
    Reg#(Bit#(8)) count_sent_reg <- mkReg(0);

    // input reg
    Reg#(Bit#(32)) miso_shift_r <- mkRegU();

    // output regs
    Wire#(Bool) cs_r <- mkBypassWire();
    rule set_cs; cs_r <= (count_sent_reg > 0) && (init_r == 0); endrule
    Reg#(Bit#(1)) mosi_r <- mkReg(0);
    Reg#(Bit#(1)) cs_suppress_r <- mkReg(0);
    // enforce break during xmission
    Reg#(Bool) break_enforced <- mkRegU;

    // shift out data
    rule send_data if (cs_r && falling_edge);
        mosi_r <= truncateLSB(command_reg);
        cs_suppress_r <= truncateLSB(suppress_cs_reg);
        command_reg <= command_reg << 1;
        suppress_cs_reg <= suppress_cs_reg << 1;
        count_sent_reg <= count_sent_reg - 1;
        break_enforced <= False;
    endrule

    //gen clock
    Reg#(Bit#(1)) clk_r <- mkReg(0);
    rule gen_clk;
        clk_r <= pack((clkdiv[0] >= clk_div_in>>1) && cs_r._read() && !unpack(cs_suppress_r));
    endrule

    // enforce pause between packets
    rule break_done if (!cs_r && falling_edge);
        break_enforced <= True;
    endrule

    Wire#(Bit#(1)) miso_w <- mkBypassWire();
    Vector#(2, Reg#(Bit#(2))) miso_sync <- replicateM(mkRegU);
    rule sync_miso;
        miso_sync[0] <= {miso_w, pack(rising_edge)};
        miso_sync[1] <= miso_sync[0];
    endrule

    rule read_miso if (cs_r && unpack(miso_sync[1][0]));
        miso_shift_r <= truncate({miso_shift_r, miso_sync[1][1]});
    endrule

    Reg#(Maybe#(Bit#(idx_width))) inflight_id <- mkReg(tagged Invalid);
    Reg#(Bool) r_nw <- mkRegU;

    PulseWire w_before_r <- mkPulseWire();

    // write iface
    interface Server w;
        interface Put request;
            method Action put(Tuple4#(UInt#(XLEN), Bit#(XLEN), Bit#(4), Bit#(idx_width)) req) if (!cs_r && break_enforced && init_r == 0 && !isValid(inflight_id));
                Bit#(24) addr = pack(truncate(tpl_1(req)));
                let data = tpl_2(req);
                let strb = tpl_3(req);
                let idx = tpl_4(req);

                Vector#(4, Bit#(1)) strb_v = unpack(strb); 
                Vector#(4, Bit#(40)) strb_ext = map(compose(pack, replicate), strb_v);

                // send packet
                command_reg     <= {8'b00000110, 1'b0, 8'b00000010,  addr+3, data[7:0], 1'b0,   8'b00000010, addr+2, data[15:8], 1'b0,    8'b00000010, addr+1,  data[23:16], 1'b0,   8'b00000010, addr, data[31:24]};
                suppress_cs_reg <= {8'b0, 1'b1, ~strb_ext[0], 1'b1, ~strb_ext[1], 1'b1, ~strb_ext[2], 1'b1, ~strb_ext[3]};
                count_sent_reg  <= 173;

                // store id
                inflight_id <= tagged Valid idx;
                r_nw <= False;

                // inhibit r
                //w_before_r.send();

                clkdiv[1] <= 0;
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Bit#(idx_width)) get() if (inflight_id matches tagged Valid .v &&& !cs_r &&& !r_nw);
                inflight_id <= tagged Invalid;
                return v;
            endmethod
        endinterface
    endinterface


    // write iface
    interface Server r;
        interface Put request;
            method Action put(Tuple2#(UInt#(XLEN), Bit#(idx_width)) req) if (!cs_r && break_enforced && init_r == 0 && !w_before_r && !isValid(inflight_id));
                Bit#(24) addr = pack(truncate(tpl_1(req)));
                let idx = tpl_2(req);

                // send packet
                command_reg     <= {8'b00000011,  addr, 0};
                suppress_cs_reg <= {0};
                count_sent_reg  <= 65;

                // store id
                inflight_id <= tagged Valid idx;
                r_nw <= True;

                clkdiv[1] <= 0;
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(idx_width))) get() if (inflight_id matches tagged Valid .v &&& !cs_r &&& r_nw);
                inflight_id <= tagged Invalid;
                return tuple2(miso_shift_r, v);
            endmethod
        endinterface
    endinterface


    interface spi_cs = !(cs_r && !unpack(cs_suppress_r));
    interface spi_clk = clk_r;

    method Action spi_miso(Bit#(1) i);
        miso_w <= i;
    endmethod

    method Bit#(1) spi_mosi = mosi_r._read();

    method Action set_clkdiv(Bit#(32) in) = clk_div_in._write(in);
endmodule

endpackage
