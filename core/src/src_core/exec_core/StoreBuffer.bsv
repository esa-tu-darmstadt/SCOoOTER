package StoreBuffer;

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Types::*;
import Inst_Types::*;
import Interfaces::*;
import GetPut::*;
import Vector::*;
import TestFunctions::*;
import ClientServer::*;
import GetPut::*;
import Debug::*;

// This is the internal storage
// the real unit is written below

interface InternalStoreIFC#(numeric type entries);
    method Action enq(MemWr data);
    method Action deq();
    method MemWr first();
    method ActionValue#(Maybe#(MaskedWord)) forward(UInt#(XLEN) addr);
    method Bool empty();
    method Bool full();
endinterface

module mkInternalStore(InternalStoreIFC#(entries)) provisos (
    // create types for amount tracking
    Log#(entries, idx_t),
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, amount_t),
    // the id type is smaller or equal to
    // the count type as counting can hold
    // one further value
    Add#(b__, idx_t, amount_t)
);
    // internal store
    Vector#(entries, Reg#(MemWr)) storage <- replicateM(mkRegU());
    // pointers
    Reg#(UInt#(idx_t)) head_r <- mkReg(0);
    Reg#(UInt#(idx_t)) tail_r <- mkReg(0);
    // full flags
    Array#(Reg#(Bool)) full_r <- mkCReg(2, False);

    // if the pointers are dissimilar, buffer cannot be full
    rule flush_full;
        if(head_r != tail_r) full_r[0] <= False;
    endrule

    // remove an entry
    PulseWire clear_w <- mkPulseWire();
    rule clear if (clear_w);
        tail_r <= tail_r + 1;
    endrule

    // this limits us to pwr2 depths
    // TODO: fix this
    function UInt#(idx_t) truncate_idx(UInt#(idx_t) a, UInt#(idx_t) b) = a + b;

    // enqueue store requests
    method Action enq(MemWr data) if (!full_r[1]);
        // move pointers forward
        let new_head = truncate_idx(head_r, 1);
        head_r <= new_head;
        if (tail_r == new_head) full_r[1] <= True;
        storage[head_r] <= data;
    endmethod
    // ready, deq and first functions similar to MIMO
    method Action deq() if ( !(tail_r == head_r && !full_r[0]) ) = clear_w.send();
    method MemWr first() if ( !(tail_r == head_r && !full_r[0]) ) = readVReg(storage)[tail_r];
    // forward signals - this is used to find data in the buffer to fwd to read operations
    method ActionValue#(Maybe#(MaskedWord)) forward(UInt#(XLEN) addr);
        actionvalue
            Maybe#(MaskedWord) result = tagged Invalid;
            Bool done = False;
            for(Integer i = 0; i < valueOf(entries); i=i+1) begin // loop through the buffer
                let current_idx = truncate_idx(tail_r, fromInteger(i));
                if((current_idx != head_r || full_r[1])) begin
                    if(addr == storage[current_idx].mem_addr && !done) begin // compare address
                        result = tagged Valid MaskedWord { data: storage[current_idx].data, store_mask: storage[current_idx].store_mask };
                    end
                end else if(current_idx == head_r && !full_r[1]) done = True;
            end
        return result;
        endactionvalue
    endmethod
    // test if the store buffer is empty - needed for atomic rl
    method Bool empty() = (tail_r == head_r && !full_r[0]);
    method Bool full() = full_r[0];
endmodule


// unit implementation

`ifdef SYNTH_SEPARATE
    (* synthesize *)
`endif
module mkStoreBuffer(StoreBufferIFC);

    // create internal buffer
    InternalStoreIFC#(STORE_BUF_DEPTH) internal_buf <- mkInternalStore();
    // FIFO to hold outgoing write requests until they are completed (important for fwd)
    FIFOF#(MemWr) pending_buf <- mkPipelineFIFOF();
    // wire for incoming data
    PulseWire dequeue_incoming_w <- mkPulseWire();

    // helper functions: check if addr fits and create a MaskedWord struct from a MemWr struct
    function Bool find_addr(UInt#(XLEN) addr, Maybe#(MemWr) mw) = (mw matches tagged Valid .w ? w.mem_addr == addr : False); 
    function MaskedWord mw_from_memory_write(MemWr in) = MaskedWord {data: in.data, store_mask: in.store_mask};
    
    // forward memory data - create a wire which holds pending requests or a default value
    Wire#(UInt#(XLEN)) forward_test_addr_w <- mkBypassWire();
    Wire#(MemWr) forward_pending <- mkDWire(MemWr {mem_addr: 0, store_mask: ?, data: ?});
    rule fwd_pend;
        forward_pending <= pending_buf.first();
    endrule

    // real forwarding
    interface Server forward;
        interface Put request;
            method Action put(UInt#(XLEN) a) = forward_test_addr_w._write(a);
        endinterface
        interface Get response;
            method ActionValue#(Maybe#(MaskedWord)) get();
                actionvalue
                    // extract addr
                    let addr = forward_test_addr_w;

                    // check internal buffer
                    let internal_store_res <- internal_buf.forward(addr);

                    // check pending store
                    Maybe#(MaskedWord) pending_store_res = 
                        (forward_pending.mem_addr == addr && forward_pending.mem_addr != 0 ?
                        tagged Valid MaskedWord {data: forward_pending.data, store_mask: forward_pending.store_mask} :
                        tagged Invalid);

                    // check incoming buffer
                    // extract matching data
                    // Maybe#(Maybe#(MemWr)) incoming_resp = Vector::find(find_addr(addr), Vector::reverse(incoming_writes_w));
                    // Maybe#(MaskedWord) incoming_res = isValid(incoming_resp) ? 
                    //    tagged Valid mw_from_memory_write(incoming_resp.Valid.Valid) : 
                    //    tagged Invalid;

                    // internal buffer has a higher priority than pending store since those inst were later
                    // incoming buffer is highest priority
                    let result = (internal_store_res matches tagged Valid .v ? internal_store_res : pending_store_res);

                    return result;
                endactionvalue
            endmethod
        endinterface
    endinterface

    // put write requests in from LSU
    interface Put memory_write;
        method Action put(MemWr m);
            internal_buf.enq(m);
        endmethod
    endinterface

    // interface for write dequeueing
    interface Client write;
        interface Get request;
            method ActionValue#(MemWr) get();
                actionvalue
                    internal_buf.deq();
                    pending_buf.enq(internal_buf.first());
                    return internal_buf.first();
                endactionvalue
            endmethod
        endinterface
        interface Put response;
            method Action put(void v);
                pending_buf.deq();
            endmethod
        endinterface
    endinterface

    // signal empty/full buffer to outside
    method Bool empty() = internal_buf.empty() && pending_buf.notFull();
    method Bool full() = internal_buf.full();
endmodule

endpackage