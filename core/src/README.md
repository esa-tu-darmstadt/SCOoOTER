# Source Code of the SCOoOTER Processor

This folder contains SCOoOTERs BSV source code. The code is organized into multiple folders.
`src_core` contains the CPU implementation, memory arbitration, and generic type definition.
`src_bus` contains and periphery and interconnects.
`src_openlane` contains the ASIC wrapper.
`src_soc` contains the FPGA wrapper.
`src_test` contains the testbenches.
`BVI` contains Verilog-modules which are used in the BSV code.

Additionally, configuration source files are placed here:
`Config` is SCOoOTERs main configuration and the entrypoint for experimentation.
`Debug` contains settings for the debugging infrastructure.