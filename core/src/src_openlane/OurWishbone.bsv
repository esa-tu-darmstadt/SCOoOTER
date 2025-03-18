package OurWishbone;
    import FIFO::*;
    import FIFOF::*;
    import ClientServer::*;
    import GetPut::*;
    import Memory::*;
    import Connectable::*;

    interface WishboneMaster_IFC#(numeric type aw, numeric type dw);
    (* prefix="" *)
    (* always_ready, always_enabled *) method Action put((* port="STALL_I" *) Bool stall,
                                                         (* port="ACK_I" *)   Bool ack,
                                                         (* port="DAT_I" *)   Bit#(dw) dat);
    (* always_ready, result="CYC_O" *) method Bool     cyc();
    (* always_ready, result="STB_O" *) method Bool     stb();
    (* always_ready, result="WE_O" *)  method Bool     we();
    (* always_ready, result="ADR_O" *) method Bit#(aw) adr();
    (* always_ready, result="SEL_O" *) method Bit#(TDiv#(dw, 8)) sel();
    (* always_ready, result="DAT_O" *) method Bit#(dw) dat();
    endinterface

    interface WishboneSlave_IFC#(numeric type aw, numeric type dw);
    (* prefix="" *)
    (* always_ready, always_enabled *) method Action put((* port="CYC_I" *) Bool cyc,
                                                         (* port="STB_I" *) Bool stb,
                                                         (* port="WE_I" *)  Bool we,
                                                         (* port="ADR_I" *) Bit#(aw) adr,
                                                         (* port="SEL_I" *) Bit#(TDiv#(dw, 8)) sel,
                                                         (* port="DAT_I" *) Bit#(dw) dat);

    (* always_ready, result="STALL_O" *) method Bool     stall();
    (* always_ready, result="ACK_O" *)   method Bool     ack();
    (* always_ready, result="DAT_O" *)   method Bit#(dw) dat();
    endinterface

    instance Connectable#(WishboneMaster_IFC#(aw, dw), WishboneSlave_IFC#(aw, dw));
   module mkConnection#(WishboneMaster_IFC#(aw, dw) wbm, WishboneSlave_IFC#(aw, dw) wbs) (Empty);
      (* fire_when_enabled, no_implicit_conditions *)
      rule rl_connect;
         wbm.put(wbs.stall, wbs.ack, wbs.dat);
      endrule

      rule connect2;
         wbs.put(wbm.cyc, wbm.stb, wbm.we, wbm.adr, wbm.sel, wbm.dat);
      endrule
   endmodule
endinstance

    interface WishboneMasterXactor_IFC#(numeric type aw, numeric type dw);
        (* prefix="" *)
        interface WishboneMaster_IFC#(aw, dw)                          wishbone;
        interface Server#(MemoryRequest#(aw, dw), MemoryResponse#(dw)) server;
    endinterface

    interface WishboneSlaveXactor_IFC#(numeric type aw, numeric type dw);
        (* prefix="" *)
        interface WishboneSlave_IFC#(aw, dw) wishbone;
        interface Client#(MemoryRequest#(aw, dw), MemoryResponse#(dw)) client;
    endinterface

    typedef enum {IDLE, ACTIVE} FSMState deriving (Bits, Eq);

    module mkWishboneMasterXactor#(parameter Integer n) (WishboneMasterXactor_IFC#(aw, dw));
        FIFOF#(MemoryRequest#(aw, dw)) io_req    <- mkGFIFOF(False, True);
        FIFOF#(MemoryResponse#(dw))    io_rsp    <- mkGFIFOF(True, False);
    
        Wire#(Bool) ack_w <- mkDWire(False);
        
        Bool stb_val = io_req.notEmpty && !ack_w;

        interface server = toGPServer(io_req, io_rsp);

        interface WishboneMaster_IFC wishbone;
            method Action put(Bool stall, Bool ack, Bit#(dw) dat);
                // We ignore stall since we don't support pipeline mode
                ack_w <= ack;
                io_rsp.enq(MemoryResponse {data: dat});
                io_req.deq;
            endmethod
 
            method Bool cyc();
                return io_req.notEmpty;
            endmethod
  
            method Bool               stb() = stb_val;
            method Bool               we()  = io_req.first.write;
            method Bit#(aw)           adr() = io_req.first.address;
            method Bit#(TDiv#(dw, 8)) sel() = io_req.first.byteen;
            method Bit#(dw)           dat() = io_req.first.data;
        endinterface
    endmodule

    module mkWishboneSlaveXactor#(parameter Integer n)(WishboneSlaveXactor_IFC#(aw, dw));
        FIFOF#(MemoryRequest#(aw, dw)) io_req    <- mkGFIFOF(True, False);
        FIFOF#(MemoryResponse#(dw))    io_rsp    <- mkFIFOF();

        Wire#(Bool) stb_w <- mkDWire(False);
        Wire#(Bool) cyc_w <- mkDWire(False);
        Reg#(Bool) ack_outstanding <- mkReg(False);
        
        Wire#(Bit#(dw)) dat_o_w <- mkDWire(?);

        rule deq_rsp;
            $display("our wishbone");
            io_rsp.deq;
            dat_o_w <= io_rsp.first().data;
            ack_outstanding <= False;
        endrule

        interface client = toGPClient(io_req, io_rsp);

        interface WishboneSlave_IFC wishbone;
            method Action put(Bool cyc, Bool stb, Bool we, Bit#(aw) adr, Bit#(TDiv#(dw, 8)) sel, Bit#(dw) dat);
                if(io_req.notFull && cyc && stb && !ack_outstanding) begin
                    MemoryRequest#(aw, dw) req = MemoryRequest {
                        write: we,
                        byteen: sel,
                        address: adr,
                        data: dat
                    };
                    io_req.enq(req);
                    ack_outstanding <= True;
                end
                stb_w <= stb;
                cyc_w <= cyc;
            endmethod : put

            method Bool stall() = !io_req.notFull;
            method Bool ack() = stb_w && cyc_w && io_rsp.notEmpty;
            method Bit#(dw) dat() = dat_o_w;
        endinterface
    endmodule

endpackage