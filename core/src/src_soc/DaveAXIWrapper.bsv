package DaveAXIWrapper;
    import FIFO::*;
    import GetPut::*;
    import ClientServer::*;
    import BlueAXI::*;
    import Types::*;
    import SCOOOTER_riscv::*;
    import Config::*;
    import Interfaces::*;
    import Dave::*;

module mkDaveAXIWrapper(DaveAXIWrapper);
    DaveIFC dave <- mkDave();
    AXI4_Lite_Master_Rd#(XLEN, TMul#(XLEN, IFUINST)) m_axi_imem_rd <- mkAXI4_Lite_Master_Rd(2);
    AXI4_Lite_Master_Wr#(XLEN, TMul#(XLEN, IFUINST)) m_axi_imem_dummy_wr <- mkAXI4_Lite_Master_Wr_Dummy();
    AXI4_Lite_Master_Rd#(XLEN, XLEN) m_axi_dmem_rd <- mkAXI4_Lite_Master_Rd(2);
    AXI4_Lite_Master_Wr#(XLEN, XLEN) m_axi_dmem_wr <- mkAXI4_Lite_Master_Wr(2);

    FIFO#(Bit#(TLog#(NUM_CPU))) imem_cpu <- mkFIFO;
    FIFO#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) dread_cpu <- mkFIFO;
    FIFO#(Bit#(TAdd#(TLog#(NUM_CPU), 1))) dwrite_cpu <- mkFIFO;

    rule conn_inst_arbiter_req;
        match {.addr, .core} <- dave.imem_r.request.get();
        imem_cpu.enq(core);
        axi4_lite_read(m_axi_imem_rd, pack(addr));
    endrule

    rule conn_inst_arbiter_rsp;
        let r <- m_axi_imem_rd.response.get();
        let cpu <- toGet(imem_cpu).get();
        dave.imem_r.response.put(tuple2(
            r.data,
            cpu
        ));
    endrule

    rule conn_data_arbiter_rd_req;
        match {.addr, .core_amo} <- dave.dmem_r.request.get();
        dread_cpu.enq(core_amo);
        axi4_lite_read(m_axi_dmem_rd, pack(addr));
    endrule

    rule conn_data_arbiter_rd_rsp;
        let r <- m_axi_dmem_rd.response.get();
        let cpu_amo <- toGet(dread_cpu).get();
        dave.dmem_r.response.put(tuple2(
            r.data,
            cpu_amo
        ));
    endrule

    rule conn_data_arbiter_wr_req;
        match {.addr, .data, .strb, .core_amo} <- dave.dmem_w.request.get();
        dwrite_cpu.enq(core_amo);
        axi4_lite_write_strb(m_axi_dmem_wr, pack(addr), data, strb);
    endrule

    rule conn_data_arbiter_wr_rsp;
        let r <- m_axi_dmem_wr.response.get();
        let cpu_amo <- toGet(dwrite_cpu).get();
        dave.dmem_w.response.put(
            cpu_amo
        );
    endrule

    // Interface implementation
    method sw_int = dave.sw_int;
    method timer_int = dave.timer_int;
    method ext_int = dave.ext_int;

    `ifdef EVA_BR
        method correct_pred_br = dave.correct_pred_br;
        method wrong_pred_br = dave.wrong_pred_br;
        method correct_pred_j = dave.correct_pred_j;
        method wrong_pred_j = dave.wrong_pred_j;
    `endif

    interface imem_r = m_axi_imem_rd.fab;
    interface imem_w = m_axi_imem_dummy_wr.fab;
    interface dmem_r = m_axi_dmem_rd.fab;
    interface dmem_w = m_axi_dmem_wr.fab;

    `ifdef DEXIE
        interface dexie = dave.dexie;
    `endif
endmodule : mkDaveAXIWrapper
endpackage : DaveAXIWrapper