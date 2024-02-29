# Features and Options

SCOoOTER supports the following features:

- RV32IMA Instruction Set
- Branch Prediction (none, smiths, gshare, gskewed)
- Call/Return prediction (none, RAS, BTB)
- Instruction Reordering (via Tomasulos algorithm)
- Superscalar execution
- Configurable address map
- Separate IMEM and DMEM busses
- Custom simple bus interface and AXI4 Full or Lite via adapters
- Multithread and Multicore architectures

Many features are configurable:

| Configuration option | Explanation |
|----------------------|-------------|
| IFUINST              | Amount of instructions fetched per cycle. This option increases IFU complexity and the bus width of the instruction bus. |
| ISSUEWIDTH           | Maximum amount of instructions issued per cycle. Powers of two are recommened since that decreases complexity but other values work too. |
| RESETVEC             | First address to read an instruction from. |
| BASE_DMEM            | Base address of the data memory. |
| SIZE_DMEM            | Size (in bytes) of the DMEM. |
| BASE_IMEM            | Base address of the instruction memory. |
| SIZE_IMEM            | Size (in bytes) of the IMEM. |
| ROBDEPTH             | Size of the reorder buffer / Amount of in-flight instructions in the exec core. Should be divisible by the issuewidth. |
| INST_WINDOW          | Size of the buffer between decode and issue. |
| MUL_DIV_STRATEGY     | The multiply/divide unit can be implemented in different ways. 0: single-cycle: This may be well suited for FPGA but severely limits ASIC performance. 1: multi-cycle: Iterative calculation. 2: pipelined: full pipeline implementation. The latency for 1 and 2 is 32 cycles. |
| NUM_ALU              | How many ALU units should be instantiated? |
| NUM_MULDIV           | How many Multiply/Divide units should be instantiated? 0 disables the M extension |
| NUM_BR               | How many branch units should be instantiated? |
| REGFILE_LATCH_BASED  | Use a latch-based registerfile |
| REGEVO_LATCH_BASED   | Use a latch-based speculative register file |
| REGCSR_LATCH_BASED   | Use a latch-based CSR file |
| RS_DEPTH_ALU         | Reservation station depth for ALU units |
| RS_DEPTH_MEM         | Reservation station depth for Load/Store unit  |
| RS_DEPTH_CSR         | Reservation station depth for CSR unit |
| RS_DEPTH_MULDIV         | Reservation station depth for multiply/divide units |
| RS_DEPTH_BR         | Reservation station depth for BR units |
| BRANCHPRED          | Type of branch direction predictor. |
| BITS_BTB            | How many bits of the instruction address are used for BTB indexing (branch target prediction). |
| BITS_PHT            | How many bits of the instruction address are used for PHT indexing (branch direction prediction). |
| BITS_BHR            | How many previous direction predictions are stored for direction prediction. |
| USE_RAS             | Should the processor use a return address stack? |
| RAS_SAVE_HEAD       | Should the head-pointer of the RAS be stored for restoration upon misprediction? |
| RAS_SAVE_FIRST       | Should the first entry of the RAS be stored for restoration upon misprediction? |
| RASDEPTH | Number of entries in the return address stack |
| STORE_BUF_DEPTH | Number of entries in the store buffer |
| NUM_CPU | Amount of cores in the system |
| NUM_THREADS | Amount of threads per core |