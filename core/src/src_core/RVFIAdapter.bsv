package RVFIAdapter;

interface RVFI;
    (* always_ready, always_enabled *)
    method Vector#(ISSUEWIDTH, RVFIBus) rvfi;
    method Action csr_in(CSRBundle c);
    method Action inst_in(InstBundle i);
endinterface

module mkRVFIAdapter;

endmodule

endpackage