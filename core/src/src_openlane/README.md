# OpenLane ASIC wrapper modules

This folder contains ASIC wrappers for OpenLane synthesis of SCOoOTER.
`SCOoOTER_Wrapper` wraps the processor cores and ties off unused interfaces.
`SoC_Config` holds config options for the SoC.
`SoC_AXI` and `SoC_WB` are ASIC implementations with an external AXI or Wishbone interface. Common functionality is implemented in `SoC_Base`. Memories can be initialized from the external bus which, in our case, is connected to the Caravel management system. The AXI implementation is used in simulation (with `TestSoC_AXI`). The Wishbone implementation is used for Caravel. `OurWishbone` provides the Wishbone implementation. Full system simulation is possible in the Caravel repository. Refer to the Caravel documentation.