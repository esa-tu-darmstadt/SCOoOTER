package OurWishbone;
    import FIFO::*;
    import FIFOF::*;
    import ClientServer::*;
    import GetPut::*;
    import Memory::*;
    import Connectable::*;

    /*
    
    Wishbone bus implementation

    */

    // Raw Interface definitions
    // Define just the wires and wraps them in a BSV-like manner
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

    // Connectable - Helper to connect a Wishbone slave and Master
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


    // BSV interaction interfaces
    // Consist of the Wishbone Wires and a BSV Server/Client for interaction from BSV
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

    // Wishbone Bus state enum
    typedef enum {IDLE, ACTIVE} FSMState deriving (Bits, Eq);

    // Implementation - translates BSV requests to Wishbone transactions - BSV is Master
    module mkWishboneMasterXactor#(parameter Integer n) (WishboneMasterXactor_IFC#(aw, dw));
        
        // Buffer Requests and Responses
        FIFOF#(MemoryRequest#(aw, dw)) io_req    <- mkGFIFOF(False, True);
        FIFOF#(MemoryResponse#(dw))    io_rsp    <- mkGFIFOF(True, False);
    
        // Wire to transport the slave's ACK signal
        Wire#(Bool) ack_w <- mkDWire(False);
        
        // generate the STB signal to start a new transaction
        Bool stb_val = io_req.notEmpty && !ack_w;

        // Convert BSV interface nto FIFOs
        interface server = toGPServer(io_req, io_rsp);

        // Generate the Wishbone signals
        interface WishboneMaster_IFC wishbone;
            // inputs from Slave
            method Action put(Bool stall, Bool ack, Bit#(dw) dat);
                // We ignore stall since we don't support pipeline mode
                ack_w <= ack;
                // Enqueue returned data into FIFO
                io_rsp.enq(MemoryResponse {data: dat});
                // dequeue request
                io_req.deq;
            endmethod
 
            // notify request to slave
            method Bool cyc();
                return io_req.notEmpty;
            endmethod
  
            // set wires according to request
            method Bool               stb() = stb_val;
            method Bool               we()  = io_req.first.write;
            method Bit#(aw)           adr() = io_req.first.address;
            method Bit#(TDiv#(dw, 8)) sel() = io_req.first.byteen;
            method Bit#(dw)           dat() = io_req.first.data;
        endinterface
    endmodule

    // Implementation - translates BSV requests to Wishbone transactions - BSV is Slave
    module mkWishboneSlaveXactor#(parameter Integer n)(WishboneSlaveXactor_IFC#(aw, dw));

        // Buffer Requests and Responses
        FIFOF#(MemoryRequest#(aw, dw)) io_req    <- mkGFIFOF(True, False);
        FIFOF#(MemoryResponse#(dw))    io_rsp    <- mkFIFOF();

        // stb and cyc signals
        Wire#(Bool) stb_w <- mkDWire(False);
        Wire#(Bool) cyc_w <- mkDWire(False);
        // store whether we must ack an outstanding request
        Reg#(Bool) ack_outstanding <- mkReg(False);
        
        // data output from our slave
        Wire#(Bit#(dw)) dat_o_w <- mkDWire(?);

        // send responses to master
        rule deq_rsp;
            io_rsp.deq;
            dat_o_w <= io_rsp.first().data;
            ack_outstanding <= False;
        endrule

        // transform BSV Client interface into FIFOs
        interface client = toGPClient(io_req, io_rsp);

        // Generate the Wishbone signals
        interface WishboneSlave_IFC wishbone;
            method Action put(Bool cyc, Bool stb, Bool we, Bit#(aw) adr, Bit#(TDiv#(dw, 8)) sel, Bit#(dw) dat);
                // get requests from Master and store them to FIFO
                if(io_req.notFull && cyc && stb && !ack_outstanding) begin
                    MemoryRequest#(aw, dw) req = MemoryRequest {
                        write: we,
                        byteen: sel,
                        address: adr,
                        data: dat
                    };
                    io_req.enq(req);
                    // also store that we must Ack the request
                    ack_outstanding <= True;
                end
                stb_w <= stb;
                cyc_w <= cyc;
            endmethod : put

            // populate output wires
            method Bool stall() = !io_req.notFull;
            method Bool ack() = stb_w && cyc_w && io_rsp.notEmpty;
            method Bit#(dw) dat() = dat_o_w;
        endinterface
    endmodule

endpackage