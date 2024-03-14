package ArianeRegFile;

import Vector::*;

/*

ArianeRegFile is a latch-based register file. It is based on the register file from the Ariane core.

*/

// single write port
interface ArianeRegWriteIfc#(type t_data);
    method Action request(Bit#(5) addr, t_data data);
endinterface

// read port
interface ArianeRegReadIfc#(type t_data);
     method Action request(Bit#(5) addr);
     method t_data response();
endinterface

// read and write ports (as well as entire contents for debugging purposes)
interface ArianeRegFileIfc#(numeric type rd_ports, numeric type wr_ports, type t_data);
    interface Vector#(rd_ports, ArianeRegReadIfc#(t_data)) rd;
    interface Vector#(wr_ports, ArianeRegWriteIfc#(t_data)) wr;
    method Vector#(32, t_data) contents;
endinterface


// wrapper for better usability - instantiates wrapped vlog module and fixes up interfaces
module mkArianeRegFile (ArianeRegFileIfc#(rd_ports, wr_ports, t_data)) provisos (
    Bits#(t_data, datawidth) // stored data must be in Bits typeclass
);

    // instantiate internal vlog reg file
    ArianeRegFileVerilogIfc#(rd_ports, wr_ports, datawidth) internal_regfile <- mkArianeRegFileVerilog();


    // wires to transport data from ported interfaces to verilog interfaces
    Vector#(rd_ports, Wire#(Bit#(5))) read_addr <- replicateM(mkDWire(0));
    Vector#(wr_ports, Wire#(Bit#(5))) write_addr <- replicateM(mkDWire(0));
    Vector#(wr_ports, Wire#(Bit#(datawidth))) write_data <- replicateM(mkDWire(0));
    Vector#(wr_ports, Wire#(Bool)) write_ena <- replicateM(mkDWire(False));

    // pass read request to regfile - single rq with all addr
    rule rd_rq;
        internal_regfile.read_rq(Vector::readVReg(read_addr));
    endrule

    // pass write request to regfile - single rq with all addr
    rule wr_rq;
        internal_regfile.write_rq(readVReg(write_addr), readVReg(write_data), pack(readVReg(write_ena)));
    endrule

    // create ported interface and separate ports
    Vector#(rd_ports, ArianeRegReadIfc#(t_data)) read_ifc = ?;
    for(Integer i = 0; i < valueOf(rd_ports); i = i+1) begin
        read_ifc[i] = (interface ArianeRegReadIfc;
            method Action request(Bit#(5) addr);
                read_addr[i] <= addr; // store address
            endmethod
            method t_data response();
                return unpack(internal_regfile.read_rs()[i]); // return result
            endmethod
        endinterface);
    end

    Vector#(wr_ports, ArianeRegWriteIfc#(t_data)) write_ifc = ?;
    for(Integer i = 0; i < valueOf(wr_ports); i = i+1) begin
        write_ifc[i] = (interface ArianeRegWriteIfc;
            method Action request(Bit#(5) addr, t_data data);
                // store write addr and data
                write_addr[i] <= addr;
                write_data[i] <= pack(data);
                // set port as enabled
                write_ena[i] <= True;
            endmethod
        endinterface);
    end

    // export interfaces
    interface rd = read_ifc;
    interface wr = write_ifc;
    interface contents = Vector::reverse(Vector::map(unpack, internal_regfile.contents));

endmodule

// verilog-like interface for BVI import
interface ArianeRegFileVerilogIfc#(numeric type rd_ports, numeric type wr_ports, numeric type datawidth);
    method Action read_rq(Vector#(rd_ports, Bit#(5)) addrs);
    method Vector#(rd_ports, Bit#(datawidth)) read_rs();
    method Action write_rq(Vector#(wr_ports, Bit#(5)) addrs, Vector#(wr_ports, Bit#(datawidth)) data, Bit#(wr_ports) ena);
    method Vector#(32, Bit#(datawidth)) contents;
endinterface

// VLog import
import "BVI" ariane_regfile_lol =
module mkArianeRegFileVerilog (ArianeRegFileVerilogIfc#(rd_ports, wr_ports, datawidth));

    // set all parameters
    parameter DATA_WIDTH     = valueOf(datawidth);
    parameter NR_READ_PORTS  = valueOf(rd_ports);
    parameter NR_WRITE_PORTS = valueOf(wr_ports);
    parameter ZERO_REG_ZERO  = 1; // 0th register is always zero

    // set up clk and RST
    default_clock clk (clk_i, (*unused*) clk_gate);
	default_reset rst (rst_ni);

    // never use test inputs
    port test_en_i = 0;

    // bind verilog wires to methods
    method read_rq(raddr_i) enable((*inhigh*) ena);
    method rdata_o read_rs;
    method write_rq(waddr_i, wdata_i, we_i) enable((*inhigh*) ena2);
    method rdata_full_o contents;

    // set up scheduling
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

// single register import - uses same interface as default Reg
import "BVI" ariane_reg =
module mkArianeReg#(Bit#(datawidth) init) (Reg#(data_t)) provisos (
    Bits#(data_t, datawidth)
);

    parameter DATA_WIDTH     = valueOf(datawidth); // width of stored data
    parameter INIT = init; // initial value

    // set up clk and reset signals
    default_clock clk (clk_i, (*unused*) clk_gate);
	default_reset rst (rst_ni);

    port test_en_i = 1'b0; // never use test signals

    // methods
    method rdata_o _read;
    method _write(wdata_i) enable(we_i);

    // scheduling
    schedule (_read) SB (_write);
endmodule
endpackage