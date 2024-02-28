package PLIC;

import Vector::*;
import ClientServer::*;
import Types::*;
import GetPut::*;
import FIFO::*;
import SpecialFIFOs::*;
import Interfaces::*;
import ConfigReg::*;
import TestFunctions::*;
import Debug::*;

interface PLICIFC#(numeric type num_periphery, numeric type prio_levels);
    interface MemMappedIFC#(25) memory_bus;
    (* always_ready, always_enabled *)
    method Vector#(NUM_HARTS, Bool) ext_interrupts_out;
    (* always_ready, always_enabled *)
    method Action interrupts_in(Vector#(num_periphery, Bool) in);
endinterface

module mkPLIC(PLICIFC#(num_periphery, prio_levels)) provisos (
    Log#(prio_levels, prio_width),
    Add#(num_periphery, 1, num_periphery_ext),
    Log#(num_periphery_ext, periphery_id_width),
    Log#(NUM_HARTS, hart_id_width),
    Log#(NUM_CPU, cpu_idx_t),
    Add#(1, cpu_idx_t, amo_cpu_idx_t),
    Add#(a__, prio_width, 32),
    Add#(b__, num_periphery_ext, 32),
    Add#(c__, periphery_id_width, 32),
    Add#(d__, num_periphery, 32)
);

    // register state
    // configuration registers
    Vector#(num_periphery, Reg#(Bit#(prio_width))) priority_regs <- replicateM(mkRegU);
    Vector#(NUM_HARTS, Reg#(Bit#(num_periphery))) enable_reg <- replicateM(mkReg(0));
    Vector#(NUM_HARTS, Reg#(UInt#(prio_width))) threshold_regs <- replicateM(mkRegU);

    // probably not needed
    Vector#(NUM_HARTS, Reg#(Bit#(prio_width))) claim_complete_regs <- replicateM(mkRegU);

    // internal state
    Reg#(Bit#(num_periphery)) pending_reg <- mkReg(0);

    // on claim, set bit to true, on release to false
    Vector#(num_periphery, Array#(Reg#(Bool))) periphery_currently_handled <- replicateM(mkCReg(2, False));
    Vector#(num_periphery, Reg#(Bool)) periphery_currently_handled_0 = Vector::map(disassemble_creg(0), periphery_currently_handled);

    
    // internal signals for computation
    Wire#(Vector#(NUM_HARTS, Vector#(prio_levels, Vector#(num_periphery, Bool)))) irq_matrix <- mkBypassWire();
    Wire#(Vector#(NUM_HARTS, Vector#(prio_levels, Bool))) prio_with_irq <- mkBypassWire();
    Wire#(Vector#(NUM_HARTS, Vector#(prio_levels, Bool))) max_prio_with_irq <- mkBypassWire();
    Wire#(Vector#(NUM_HARTS, Vector#(num_periphery, Bool))) periphery_with_highest_irq <- mkBypassWire();
    Wire#(Vector#(NUM_HARTS, UInt#(periphery_id_width))) selected_max_interrupt <- mkBypassWire();
    Wire#(Vector#(NUM_HARTS, Vector#(prio_levels, Bool))) threshold_mask <- mkBypassWire();
    Wire#(Vector#(num_periphery, Bool)) incoming_int_signals <- mkBypassWire();

    // outgoing interrupt signals
    Reg#(Vector#(NUM_HARTS, Bool)) int_flags <- mkReg(unpack(0));


    // compute which interrupts should be triggered
    Reg#(Bit#(num_periphery)) pending_buffer_wire <- mkBypassWire();
    rule fwd_pending_wires;
        pending_reg <= pending_buffer_wire;
    endrule
    rule debug_message_pending if (pending_buffer_wire != pending_reg);
        dbg_print(PLIC, $format("Pending changed: ", fshow(pending_buffer_wire)));
    endrule
    rule calculate_pending_ints;
        pending_buffer_wire <= unpack((pack(pending_reg) | pack(incoming_int_signals)) & ~pack(readVReg(periphery_currently_handled_0)));
    endrule



    // compute a patrix for each hart which has
    // priorities and sources as axes.
    // The matrix entries are Boolean values.
    // A true value signals that the interrupt of device x has priority y and is currently pending.
    rule fill_irq_matrix;
        Vector#(NUM_HARTS, Vector#(prio_levels, Vector#(num_periphery, Bool))) local_irq_matrix = ?;
        for(Integer hart = 0; hart < valueOf(NUM_HARTS); hart=hart+1)
            for(Integer prio = 1; prio < valueOf(prio_levels); prio=prio+1) // start at 1 since priority 0 means disabled interrupt
                for(Integer src = 0; src < valueOf(num_periphery); src=src+1) begin
                    local_irq_matrix[hart][prio][src] = (priority_regs[src]==fromInteger(prio)) && unpack(pending_reg[src]) && unpack(enable_reg[hart][src]);
                end
        irq_matrix <= local_irq_matrix;
    endrule


    // create a Vector per hart, which has a bit'for each priority level
    // the bit is high, if for said hart, there is a pending interrupt at that level
    rule find_prio_levels_with_irq;
        Vector#(NUM_HARTS, Vector#(prio_levels, Bool)) local_prio_level_with_int = unpack(0);
        for(Integer hart = 0; hart < valueOf(NUM_HARTS); hart=hart+1)
            for(Integer prio = 1; prio < valueOf(prio_levels); prio=prio+1) begin
                local_prio_level_with_int[hart][prio] = Vector::elem(True, irq_matrix[hart][prio]);
            end
        prio_with_irq <= local_prio_level_with_int;
    endrule


    // for each hart, create a one-hot vector, which encodes the highest priority with a pending interrupt, if any
    // no bit is set if there is no pending interrupt for said hart
    rule find_highest_prio_with_request;
        Vector#(NUM_HARTS, Vector#(prio_levels, Bool)) local_prio_level_with_int = unpack(0);
        for(Integer hart = 0; hart < valueOf(NUM_HARTS); hart=hart+1) begin
            Bool done = False;
            for(Integer prio = valueOf(prio_levels)-1; prio > 0; prio=prio-1) begin
                local_prio_level_with_int[hart][prio] = done ? False : prio_with_irq[hart][prio];
                done = done || prio_with_irq[hart][prio];
            end
        end
        max_prio_with_irq <= local_prio_level_with_int;
    endrule


    // for each hart, create a vector with a bit per periphery component
    // the bit is high, if the interrupt is (a) at the highest interrupt level currently seen for said hart and
    // (b) pending.
    rule find_active_sources;
        Vector#(NUM_HARTS, Vector#(num_periphery, Bool)) local_periphery_with_highest_irq = unpack(0);
        for(Integer hart = 0; hart < valueOf(NUM_HARTS); hart=hart+1)
            for(Integer prio = 1; prio < valueOf(prio_levels); prio=prio+1) begin
                local_periphery_with_highest_irq[hart] = unpack( pack(local_periphery_with_highest_irq[hart]) | (pack(replicate(max_prio_with_irq[hart][prio])) & pack(irq_matrix[hart][prio])) );
            end
        periphery_with_highest_irq <= local_periphery_with_highest_irq;
    endrule

    // from the previously created vector, select the first entry and provide it as one claim_id per hart
    rule select_max_interrupt;
        Vector#(NUM_HARTS, UInt#(periphery_id_width)) claim_id = unpack(0);
        for(Integer hart = 0; hart < valueOf(NUM_HARTS); hart=hart+1)
            for(Integer src = valueOf(num_periphery_ext)-1; src > 0; src=src-1) begin
                if (periphery_with_highest_irq[hart][src-1]) claim_id[hart] = fromInteger(src);
            end
        selected_max_interrupt <= claim_id;
    endrule

    // per hart, create a vector of one bit per priv level, where levels accepted by said hart are true
    rule compute_threshold_mask;
        Vector#(NUM_HARTS, Vector#(prio_levels, Bool)) local_threshold_mask = unpack(0);
        let threshold = Vector::readVReg(threshold_regs);
        for(Integer hart = 0; hart < valueOf(NUM_HARTS); hart=hart+1) begin
            let max_prio = valueOf(prio_levels)-1;
            local_threshold_mask[hart][max_prio] = (threshold[hart] != fromInteger(max_prio));
            for(Integer prio = valueOf(prio_levels)-2; prio > 0; prio=prio-1) begin
                local_threshold_mask[hart][prio] = (threshold[hart] != fromInteger(prio)) && local_threshold_mask[hart][prio+1];
            end
        end
        threshold_mask <= local_threshold_mask;
    endrule

    // set interrupt bits for every hart
    rule set_int_flags;
        Vector#(NUM_HARTS, Bool) local_int_flags = ?;

        for(Integer hart = 0; hart < valueOf(NUM_HARTS); hart=hart+1)
            local_int_flags[hart] = Vector::elem(True, unpack(pack(threshold_mask[hart]) & pack(prio_with_irq[hart])) );
        
        int_flags <= local_int_flags;

        if (int_flags != local_int_flags)
            dbg_print(PLIC, $format("Outgoing int changed: ", fshow(local_int_flags)));
    endrule




    //register map

    // forwarding of data
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_r_fifo <- mkSizedFIFO(4);
    FIFO#(Bit#(amo_cpu_idx_t)) inflight_ids_w_fifo <- mkSizedFIFO(4);
    Reg#(Bit#(32)) read_val <- mkRegU();

    // connection to memory bus
    interface MemMappedIFC memory_bus;

        // reading registers
        interface Server mem_r;
            interface Put request;
                method Action put(Tuple2#(UInt#(25), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    let addr = tpl_1(req);

                    // interrupt src priority
                    if (addr >= 4 && addr <= 'hffc) begin
                        read_val <= extend(priority_regs[(addr >> 2) - 1]);
                    end

                    // pending bits are not writable
                    if (addr == 'h1000) begin
                        read_val <= extend({pending_reg, 1'h0});
                    end

                    // src enable bits
                    if (addr >= 'h2000 && addr < 200000) begin
                        UInt#(hart_id_width) idx = truncate(addr >> 7);
                        read_val <= extend({enable_reg[idx], 1'h0});
                    end

                    // priority threshold registers
                    if (addr > 'h200000 && truncate(addr) == 12'h000) begin
                        UInt#(hart_id_width) idx = truncate(addr >> 12);
                        read_val <= pack(extend(threshold_regs[idx]));
                    end

                    // claim/complete registers
                    if (addr > 'h200000 && truncate(addr) == 12'h004) begin
                        UInt#(hart_id_width) idx = truncate(addr >> 12);
                        let claimed_id = selected_max_interrupt[idx];
                        read_val <= pack(extend(claimed_id));
                        if (claimed_id != 0) periphery_currently_handled[claimed_id-1][0] <= True;
                        dbg_print(PLIC, $format("Claiming int: ", fshow(claimed_id)));
                    end

                    inflight_ids_r_fifo.enq(tpl_2(req));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Tuple2#(Bit#(XLEN), Bit#(TAdd#(TLog#(NUM_CPU), 1)))) get();
                    inflight_ids_r_fifo.deq();
                    return tuple2(read_val, inflight_ids_r_fifo.first());
                endmethod
            endinterface
        endinterface

        // writing registers
        interface Server mem_w;
            interface Put request;
                method Action put(Tuple4#(UInt#(25), Bit#(XLEN), Bit#(4), Bit#(TAdd#(TLog#(NUM_CPU), 1))) req);
                    

                    let addr = tpl_1(req);
                    let data = tpl_2(req);

                    // interrupt src priority
                    if (addr >= 4 && addr <= 'hffc) begin
                        priority_regs[(addr >> 2) - 1] <= truncate(data);
                        dbg_print(PLIC, $format("Setting src priority: ", fshow(data)));
                    end

                    // pending bits are not writable
                    if (addr == 'h1000) begin

                    end

                    // src enable bits
                    if (addr >= 'h2000 && addr < 'h200000) begin
                            UInt#(hart_id_width) idx = truncate(addr >> 7);
                            enable_reg[idx] <= truncate(data >> 1);
                            dbg_print(PLIC, $format("Enabling int: ", fshow(idx), " ", fshow(data >> 1)));
                    end

                    // priority threshold registers
                    if (addr >= 'h200000 && truncate(addr) == 12'h000) begin
                        UInt#(hart_id_width) idx = truncate(addr >> 12);
                        threshold_regs[idx] <= unpack(truncate(data));
                        dbg_print(PLIC, $format("Setting threshold priority: ", fshow(idx), " ", fshow(data)));
                    end

                    // claim/complete registers
                    if (addr >= 'h200000 && truncate(addr) == 12'h004) begin
                        UInt#(hart_id_width) idx = truncate(addr >> 12);
                        if (data != 0) periphery_currently_handled[data-1][1] <= False;
                        dbg_print(PLIC, $format("Completing int: ", fshow(idx), " ", fshow(data)));
                    end

                    // save id
                    inflight_ids_w_fifo.enq(tpl_4(req));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) get();
                    inflight_ids_w_fifo.deq();
                    return inflight_ids_w_fifo.first();
                endmethod
            endinterface
        endinterface
    endinterface

    // generate interrupt signals
    method Vector#(NUM_HARTS, Bool) ext_interrupts_out = int_flags;
    method Action interrupts_in(Vector#(num_periphery, Bool) in) = incoming_int_signals._write(in);

endmodule

endpackage