# BUS / Periphery

This folder contains the UNCORE environment of SCOoOTER. UNCORE refers to all periphery, modules and bus systems outside of the main processor core. An UNCORE enables the processor to be used for useful purposes since it enables the processor to communicate with the outside world.

The main UNCORE module is `IDMemAdapter`, which instantiates the processors and periphery and connects them.

`MemoryDecoder` contains helper functions to check address spaces. Basically, the functions get an address and check if this address is inside a particular memory space.

`BRamImem` and `BRamDmem` wrap BRAM memories for simulation. Those memories behave like FPGA BRAM blocks and hence return a value after 1 cycle. BRamImem scales with the fetch bus width. BRamDmem stays at 32 Bit width since we do not have scaling here.

`periphery` contains the periphery modules. Two adapters from the internal, simple memory bus to AXI full or lite. The RISC-V interrupt controllers CLINT and PLIC (refer to the RISC-V docu for more information). The RVController emulation to emulate TaPaSCo-RISC-V for the testbench.