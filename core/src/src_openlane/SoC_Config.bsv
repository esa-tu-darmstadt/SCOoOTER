package SoC_Config;

import Config::*;

/*

Most important configuration options for the SoC design

*/

// Routing MSBs for the external bus
// The MSB of external requests selects, which component should receive the request
typedef 'b00 WB_OFFSET_IMEM;
typedef 'b01 WB_OFFSET_DMEM;
typedef 'b10 WB_OFFSET_START;

/*
* Memory space configuration
* Byte amount for used SRAM macro
*/
typedef 32768 MACRO_SIZE;

endpackage