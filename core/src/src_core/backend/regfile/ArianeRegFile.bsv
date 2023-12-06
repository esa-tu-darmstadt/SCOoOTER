package ArianeRegFile;

import Vector::*;

interface ArianeRegWriteIfc#(type t_data);
    method Action request(Bit#(5) addr, t_data data);
endinterface

interface ArianeRegReadIfc#(type t_data);
     method Action request(Bit#(5) addr);
     method t_data response();
endinterface

interface ArianeRegFileIfc#(numeric type rd_ports, numeric type wr_ports, type t_data);
    interface Vector#(rd_ports, ArianeRegReadIfc#(t_data)) rd;
    interface Vector#(wr_ports, ArianeRegWriteIfc#(t_data)) wr;
    method Vector#(32, t_data) contents;
endinterface


module mkArianeRegFile (ArianeRegFileIfc#(rd_ports, wr_ports, t_data)) provisos (
    Bits#(t_data, datawidth)
);

    ArianeRegFileVerilogIfc#(rd_ports, wr_ports, datawidth) internal_regfile <- mkArianeRegFileVerilog();

    Vector#(rd_ports, Wire#(Bit#(5))) read_addr <- replicateM(mkDWire(?));

    Vector#(wr_ports, Wire#(Bit#(5))) write_addr <- replicateM(mkDWire(?));
    Vector#(wr_ports, Wire#(Bit#(datawidth))) write_data <- replicateM(mkDWire(?));
    Vector#(wr_ports, Wire#(Bool)) write_ena <- replicateM(mkDWire(False));

    rule rd_rq;
        internal_regfile.read_rq(Vector::readVReg(read_addr));
    endrule

    rule wr_rq;
        internal_regfile.write_rq(readVReg(write_addr), readVReg(write_data), pack(readVReg(write_ena)));
    endrule

    Vector#(rd_ports, ArianeRegReadIfc#(t_data)) read_ifc = ?;
    for(Integer i = 0; i < valueOf(rd_ports); i = i+1) begin
        read_ifc[i] = (interface ArianeRegReadIfc;
            method Action request(Bit#(5) addr);
                read_addr[i] <= addr;
            endmethod
            method t_data response();
                return unpack(internal_regfile.read_rs()[i]);
            endmethod
        endinterface);
    end

    Vector#(wr_ports, ArianeRegWriteIfc#(t_data)) write_ifc = ?;
    for(Integer i = 0; i < valueOf(wr_ports); i = i+1) begin
        write_ifc[i] = (interface ArianeRegWriteIfc;
            method Action request(Bit#(5) addr, t_data data);
                write_addr[i] <= addr;
                write_data[i] <= pack(data);
                write_ena[i] <= True;
            endmethod
        endinterface);
    end

    interface rd = read_ifc;
    interface wr = write_ifc;
    interface contents = Vector::reverse(Vector::map(unpack, internal_regfile.contents));

endmodule


interface ArianeRegFileVerilogIfc#(numeric type rd_ports, numeric type wr_ports, numeric type datawidth);
    method Action read_rq(Vector#(rd_ports, Bit#(5)) addrs);
    method Vector#(rd_ports, Bit#(datawidth)) read_rs();
    method Action write_rq(Vector#(wr_ports, Bit#(5)) addrs, Vector#(wr_ports, Bit#(datawidth)) data, Bit#(wr_ports) ena);
    method Vector#(32, Bit#(datawidth)) contents;
endinterface

import "BVI" ariane_regfile_lol =
module mkArianeRegFileVerilog (ArianeRegFileVerilogIfc#(rd_ports, wr_ports, datawidth));

    parameter DATA_WIDTH     = valueOf(datawidth);
    parameter NR_READ_PORTS  = valueOf(rd_ports);
    parameter NR_WRITE_PORTS = valueOf(wr_ports);
    parameter ZERO_REG_ZERO  = 1;

    default_clock clk (clk_i, (*unused*) clk_gate);
	default_reset rst (rst_ni);

    port test_en_i = 0;

    method read_rq(raddr_i) enable((*inhigh*) ena);
    method rdata_o read_rs;
    method write_rq(waddr_i, wdata_i, we_i) enable((*inhigh*) ena2);
    method rdata_full_o contents;

    schedule (read_rq) C (read_rq);
    schedule (read_rs) CF (read_rs);
    schedule (read_rq) SB (read_rs);
    schedule (read_rq) SB (write_rq);
    schedule (read_rs) SB (write_rq);
    schedule (write_rq) C (write_rq);
    schedule (contents) CF (read_rs);
    schedule (contents) CF (read_rq);
    schedule (contents) SB (write_rq);
    schedule (contents) CF (contents);
endmodule


import "BVI" ariane_reg =
module mkArianeReg#(Bit#(datawidth) init) (Reg#(data_t)) provisos (
    Bits#(data_t, datawidth)
);

    parameter DATA_WIDTH     = valueOf(datawidth);
    parameter INIT = init;

    default_clock clk (clk_i, (*unused*) clk_gate);
	default_reset rst (rst_ni);

    port test_en_i = 1'b0;

    method rdata_o _read;
    method _write(wdata_i) enable(we_i);

    schedule (_read) SB (_write);
endmodule
endpackage