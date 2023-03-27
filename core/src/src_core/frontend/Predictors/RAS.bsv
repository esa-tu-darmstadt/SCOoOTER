package RAS;

/*
  This is the Return Address Stack. It is used to predict return instruction targets.
*/

    import Types::*;
    import Inst_Types::*;
    import Ehr::*;
    import Config::*;
    import Vector::*;

    // a single prediction interface
    interface RASPort;
        method ActionValue#(Maybe#(Bit#(XLEN))) push_pop(Maybe#(Bit#(XLEN)) push, Bool pop);
        method Bit#(RAS_EXTRA) extra();
    endinterface

    // the main interface allowing for ISSUEWIDTH predictions per cycle
    interface RASIfc;
        interface Vector#(IFUINST, RASPort) ports;
        method Action redirect(Bit#(RAS_EXTRA) in);
    endinterface

    module mkRAS(RASIfc) provisos (
        // create type to track RAS index
        Log#(RASDEPTH, rasdepth_logidx_t),
        // create types for state saving and retrieval
        Mul#(RAS_SAVE_HEAD, rasdepth_logidx_t, ras_ext_head_t),
        Mul#(RAS_SAVE_FIRST, XLEN, ras_ext_first_t)
    );
        // internal storage and head pointer
        // we do not need a tail since prediction musn't be perfect
        Vector#(RASDEPTH, Ehr#(TAdd#(1, IFUINST), Bit#(XLEN))) internal_store_v <- replicateM(mkEhr(0));
        Ehr#(TAdd#(1, IFUINST), UInt#(rasdepth_logidx_t)) head_pointer <- mkEhr(0);

        // implement inc and dec functions for correct overroll
        function UInt#(rasdepth_logidx_t) head_inc(UInt#(rasdepth_logidx_t) in) = (in == fromInteger(valueOf(RASDEPTH)-1) ? 0 : in + 1);  
        function UInt#(rasdepth_logidx_t) head_dec(UInt#(rasdepth_logidx_t) in) = (in == 0 ? fromInteger(valueOf(RASDEPTH)-1) : in - 1);  

        // prediction ports
        Vector#(IFUINST, RASPort) ras_ifc = ?;
        for(Integer i = 0; i < valueOf(IFUINST); i = i+1) begin
            ras_ifc[i] = (
                interface RASPort;
                    method Bit#(RAS_EXTRA) extra();
                        // return additional information to restore RAS state once mispredicted
                        Bit#(ras_ext_head_t) h = truncate(pack(head_pointer[i+1]));
                        Bit#(ras_ext_first_t) f = truncate(internal_store_v[head_pointer[i+1]-1][i+1]);
                        return {h, f};
                    endmethod
                    method ActionValue#(Maybe#(Bit#(XLEN))) push_pop(Maybe#(Bit#(XLEN)) push_in, Bool pop);
                        actionvalue
                            Bool push = isValid(push_in);
                            let head = head_pointer[i];

                            Maybe#(Bit#(XLEN)) ret = tagged Invalid;

                            // pop off the stack
                            if(pop) begin
                                head = head_dec(head);
                                ret = tagged Valid internal_store_v[head][i];
                            end
                            // push on the stack
                            if(push) begin
                                internal_store_v[head][i] <= push_in.Valid;
                                head = head_inc(head);
                            end

                            head_pointer[i] <= head;

                            return ret;
                        endactionvalue
                    endmethod
                endinterface);
        end

        // training signals
        method Action redirect(Bit#(RAS_EXTRA) in);
            Bit#(ras_ext_head_t) h = truncateLSB(in);
            Bit#(ras_ext_first_t) f = truncate(in);

            // restore saved state
            if(valueOf(RAS_SAVE_HEAD) == 1) begin
                head_pointer[valueOf(IFUINST)] <= unpack(extend(h));
            end
            if(valueOf(RAS_SAVE_FIRST) == 1) begin
                internal_store_v[h-1][valueOf(IFUINST)] <= extend(f);
            end
        endmethod

        interface ports = ras_ifc;
    endmodule

endpackage