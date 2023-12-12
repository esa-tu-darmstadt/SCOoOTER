// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author:         Antonio Pullini - pullinia@iis.ee.ethz.ch
//
// Additional contributions by:
//                 Sven Stucki - svstucki@student.ethz.ch
//                 Markus Wegmann - markus.wegmann@technokrat.ch
//
// Design Name:    RISC-V register file
// Project Name:   zero-riscy
// Language:       SystemVerilog
//
// Description:    Register file with 31 or 15x 32 bit wide registers.
//                 Register 0 is fixed to 0. This register file is based on
//                 latches and is thus smaller than the flip-flop based RF.
//

module cluster_clock_gating
(
    input  logic clk_i,
    input  logic en_i,
    input  logic test_en_i,
    output logic clk_o
  );

  logic clk_en;

  always_latch
  begin
     if (clk_i == 1'b0)
       clk_en <= en_i | test_en_i;
  end

  assign clk_o = clk_i & clk_en;

endmodule


// single latch-based storage cell
module ariane_reg #(
    parameter int unsigned           DATA_WIDTH    = 32,
    parameter int unsigned           INIT          = 0
) (
    // clock and reset
    input  logic                                             clk_i,
    input  logic                                             rst_ni,
    // disable clock gates for testing
    input  logic                                             test_en_i,
    // read port
    output logic [DATA_WIDTH-1:0] rdata_o,
    // write port
    input  logic [DATA_WIDTH-1:0] wdata_i,
    input  logic                  we_i
);

  logic mem_clock;

  logic [           DATA_WIDTH-1:0] mem;
  logic [DATA_WIDTH-1:0] wdata_q;


  // decode addresses
  assign rdata_o = mem;

  always_ff @(posedge clk_i, negedge rst_ni) begin : sample_waddr
    if (~rst_ni) begin
      wdata_q <= '0;
    end else begin
      // enable flipflop will most probably infer clock gating
      if (we_i) begin
        wdata_q <= wdata_i;
      end
    end
  end

  // WRITE : Clock gating (if integrated clock-gating cells are available)
    cluster_clock_gating i_cg (
        .clk_i    (clk_i),
        .en_i     (we_i),
        .test_en_i(test_en_i),
        .clk_o    (mem_clock)
    );


  // Integer registers
  always_latch begin : latch_wdata
        if (~rst_ni) begin
          mem = INIT;
        end
        else if (mem_clock) mem = wdata_q;
      end
endmodule
