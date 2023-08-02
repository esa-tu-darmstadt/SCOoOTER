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
    method Action enq(UInt#(TLog#(TAdd#(ISSUEWIDTH, 1))) count, Vector#(ISSUEWIDTH, MemWr) data);
    method Bool enqReadyN(UInt#(TLog#(TAdd#(ISSUEWIDTH, 1))) count);
    method Action deq();
    method MemWr first();
    method ActionValue#(Maybe#(MaskedWord)) forward(UInt#(XLEN) addr);
    method Bool empty();
endinterface

module mkInternalStore(InternalStoreIFC#(entries)) provisos (
    // create types for amount tracking
    Log#(entries, idx_t),
    Add#(entries, 1, entries_pad_t),
    Log#(entries_pad_t, amount_t),
    // the id type is smaller or equal to
    // the count type as counting can hold
    // one further value
    Add#(b__, idx_t, amount_t),
    // issuewidth must be at least the buffer size
    Add#(c__, issuewidth_log_t, idx_t),
    // create types for instruction count tracking
    Add#(ISSUEWIDTH, 1 , issue_pad_t),
    Log#(issue_pad_t, issuewidth_log_t),
    Add#(a__, issuewidth_log_t, amount_t)
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

    // find out how many slots are full
    function UInt#(amount_t) full_slots;
        UInt#(amount_t) result;

        //calculate from head and tail pointers
        if (head_r > tail_r) result = extend(head_r) - extend(tail_r);
        else if (tail_r > head_r) result = fromInteger(valueOf(entries)) - extend(tail_r) + extend(head_r);
        // if both pointers are equal, must be full or empty
        else if (full_r[1]) result = fromInteger(valueOf(entries));
        else result = 0;

        return result;
    endfunction

    // calculate how many slots are empty
    function UInt#(amount_t) empty_slots = fromInteger(valueOf(entries)) - full_slots();

    // this limits us to pwr2 depths
    // TODO: fix this
    function UInt#(idx_t) truncate_idx(UInt#(idx_t) a, UInt#(idx_t) b) = a + b;

    // enqueue store requests
    method Action enq(UInt#(issuewidth_log_t) count, Vector#(ISSUEWIDTH, MemWr) data) if (empty_slots > 0);
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i = i+1) begin
            if(fromInteger(i) < count)
                storage[truncate_idx(head_r, fromInteger(i))] <= data[i];
        end
        // move pointers forward
        let new_head = truncate_idx(head_r, extend(count));
        head_r <= new_head;
        if(count > 0)
            if (tail_r == new_head) full_r[1] <= True;
        
    endmethod
    // ready, qeq and first functions similar to MIMO
    method Bool enqReadyN(UInt#(issuewidth_log_t) count) = (extend(count) <= empty_slots());
    method Action deq() if (full_slots() > 0) = clear_w.send();
    method MemWr first() if (full_slots() > 0) = readVReg(storage)[tail_r];
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
    Wire#(Tuple2#(Vector#(ISSUEWIDTH, Maybe#(MemWr)), UInt#(TLog#(TAdd#(ISSUEWIDTH,1))))) incoming_writes_w <- mkWire();
    PulseWire dequeue_incoming_w <- mkPulseWire();

    // flatten incloming buffer such that entries are consecutive
    rule flatten_incoming;
        let writes_in = tpl_1(incoming_writes_w);
        let cnt_in = tpl_2(incoming_writes_w);

        // remove entries beyond count
        Vector#(ISSUEWIDTH, Maybe#(MemWr)) cleaned_maybes;
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            cleaned_maybes[i] = fromInteger(i) < cnt_in ? writes_in[i] : tagged Invalid;
        end

        // remove empty slots between requests
        Vector#(ISSUEWIDTH, Maybe#(MemWr)) flattened_maybes = ?;
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            flattened_maybes[i] = find_nth_valid(i, writes_in);
        end

        // count number of elements
        Vector#(ISSUEWIDTH, MemWr) flattened = Vector::map(fromMaybe(?), flattened_maybes);
        let count = Vector::countIf(isValid, cleaned_maybes);

        // display for debugging
        for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
            if(fromInteger(i) < count) begin
                dbg_print(Mem, $format("write: ", fshow(pack(flattened[i].mem_addr)), " ", fshow(pack(flattened[i].data))));
            end
        end

        //put into MIMO buffer
        if(internal_buf.enqReadyN(count)) begin
            dequeue_incoming_w.send();
            internal_buf.enq(count, flattened);
        end
    endrule

    // helper functions: check if addr fits and create a MaskedWord struct from a MemWr struct
    function Bool find_addr(UInt#(XLEN) addr, Maybe#(MemWr) mw) = (mw matches tagged Valid .w ? w.mem_addr == addr : False); 
    function MaskedWord mw_from_memory_write(MemWr in) = MaskedWord {data: in.data, store_mask: in.store_mask};
    
    // forward memory data - create a wire which holds pending requests or a default value
    Reg#(UInt#(XLEN)) forward_test_addr_w <- mkRegU();
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
                    // remove entries beyond count (could also be wired from flatten rule)
                    Vector#(ISSUEWIDTH, Maybe#(MemWr)) cleaned_maybes;
                    for(Integer i = 0; i < valueOf(ISSUEWIDTH); i=i+1) begin
                        cleaned_maybes[i] = fromInteger(i) < tpl_2(incoming_writes_w) ? tpl_1(incoming_writes_w)[i] : tagged Invalid;
                    end
                    // extract matching data
                    Maybe#(Maybe#(MemWr)) incoming_resp = Vector::find(find_addr(addr), Vector::reverse(cleaned_maybes));
                    Maybe#(MaskedWord) incoming_res = isValid(incoming_resp) ? 
                        tagged Valid mw_from_memory_write(incoming_resp.Valid.Valid) : 
                        tagged Invalid;

                    // internal buffer has a higher priority than pending store since those inst were later
                    // incoming buffer is highest priority
                    let result = (incoming_res matches tagged Valid .vv ? 
                                  incoming_res : (internal_store_res matches tagged Valid .v ? internal_store_res : pending_store_res));

                    //dbg_print(Mem, $format("calc fwd: ", fshow(addr), " ", fshow(pending_store_res), " ", fshow(incoming_resp), " ", fshow(internal_store_res), fshow(forward_pending), fshow(incoming_writes_w)));

                    return result;
                endactionvalue
            endmethod
        endinterface
    endinterface

    method Bool deq_memory_writes() = dequeue_incoming_w;

    // put write requests in from COMMIT
    interface Put memory_writes;
        interface put = incoming_writes_w._write();
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
    method Bool empty() = internal_buf.empty() && pending_buf.notFull();
endmodule

endpackage