package DMemWrapper;

import BRAM::*;
import IN22FDX_SDPV_NPVG_W08192B016M16C064::*;

//(* conflict_free="collect_result_bank1_a,collect_result_bank2_a" *)
//(* conflict_free="collect_result_bank1_b,collect_result_bank2_b" *)
module mkDMemWrapper ( BRAM2PortBE#(UInt#(TLog#(16384)), Bit#(032), byte_en_t) ) provisos(
        Mul#(byte_en_t, 8, 032)
);

        let internal_sram_1 <- mkIN22FDX_SDPV_NPVG_W08192B016M16C064_ByteEn();
        let internal_sram_2 <- mkIN22FDX_SDPV_NPVG_W08192B016M16C064_ByteEn();
        //let internal_sram_3 <- mkIN22FDX_SDPV_NPVG_W08192B016M16C064_ByteEn();
        //let internal_sram_4 <- mkIN22FDX_SDPV_NPVG_W08192B016M16C064_ByteEn();

        Wire#(Bit#(32)) port_a_rd <- mkWire();
        Wire#(Bit#(32)) port_b_rd <- mkWire();

        rule collect_result_bank1_a;
            let upper <- internal_sram_2.portA.response.get();
            let lower <- internal_sram_1.portA.response.get();
            port_a_rd <= {upper, lower};
        endrule

        /*rule collect_result_bank2_a;
            let upper <- internal_sram_4.portA.response.get();
            let lower <- internal_sram_3.portA.response.get();
            port_a_rd <= {upper, lower};
        endrule*/

        rule collect_result_bank1_b;
            let upper <- internal_sram_2.portB.response.get();
            let lower <- internal_sram_1.portB.response.get();
            port_b_rd <= {upper, lower};
        endrule

        /*rule collect_result_bank2_b;
            let upper <- internal_sram_4.portB.response.get();
            let lower <- internal_sram_3.portB.response.get();
            port_b_rd <= {upper, lower};
        endrule*/

        interface BRAMServerBE portA;
                interface Put request;
                        method Action put(BRAMRequestBE#(UInt#(TLog#(16384)), Bit#(032), byte_en_t) in);
                                Bit#(032) bit_en;
                                for(Integer i = 0; i < 032; i=i+1)
                                        bit_en[i] = in.writeen[i/8];

                                //if(in.address < 8192) begin
                                    internal_sram_1.portA.request.put(BRAMRequestBE {writeen : in.writeen[1:0], address: truncate(in.address), datain : in.datain[15:0 ]});
                                    internal_sram_2.portA.request.put(BRAMRequestBE {writeen : in.writeen[3:2], address: truncate(in.address), datain : in.datain[31:16]});
                                /*end else begin
                                    internal_sram_3.portA.request.put(BRAMRequestBE {writeen : in.writeen[1:0], address: truncate(in.address), datain : in.datain[15:0 ]});
                                    internal_sram_4.portA.request.put(BRAMRequestBE {writeen : in.writeen[3:2], address: truncate(in.address), datain : in.datain[31:16]});
                                end*/
                        endmethod
                endinterface

                interface Get response;
                        method ActionValue#(Bit#(032)) get();
                                return port_a_rd;
                        endmethod
                endinterface
        endinterface

        interface BRAMServerBE portB;
                interface Put request;
                        method Action put(BRAMRequestBE#(UInt#(TLog#(16384)), Bit#(032), byte_en_t) in);

                                //if(in.address < 8192) begin
                                    internal_sram_1.portB.request.put(BRAMRequestBE {writeen : in.writeen[1:0], address: truncate(in.address), datain : in.datain[15:0 ]});
                                    internal_sram_2.portB.request.put(BRAMRequestBE {writeen : in.writeen[3:2], address: truncate(in.address), datain : in.datain[31:16]});
                                /*end else begin
                                    internal_sram_3.portB.request.put(BRAMRequestBE {writeen : in.writeen[1:0], address: truncate(in.address), datain : in.datain[15:0 ]});
                                    internal_sram_4.portB.request.put(BRAMRequestBE {writeen : in.writeen[3:2], address: truncate(in.address), datain : in.datain[31:16]});
                                end*/
                        endmethod
                endinterface

                interface Get response;
                        method ActionValue#(Bit#(032)) get();
                            return port_b_rd;
                        endmethod
                endinterface
        endinterface

endmodule

endpackage
