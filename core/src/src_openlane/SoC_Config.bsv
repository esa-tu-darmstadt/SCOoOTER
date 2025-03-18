package SoC_Config;

import Config::*;

/*
* Toplevel Wishbone Routing
* Caravel Userspace: 0x3000 0000 ... 0x3FFF FFFF
*  MSB 31==0, Block selection via MSBs 27...26
*  00 Scoooter IMEM
*  01 Scoooter DMEM
*  10 DExIE Tables
*  11 AXI CTRL
*
* Address range per Block; Bits 25...0 are freely usable
* 0...0x3FF FFFF = 0x0400 0000 combinations
* ca. 64 MByte per Block
*/

typedef 'b00 WB_OFFSET_IMEM;
typedef 'b01 WB_OFFSET_DMEM;
typedef 'b10 WB_OFFSET_DEX_MEM;
typedef 'b11 WB_OFFSET_AXI_CTRL;

/*
* DExIE's Internal Table Offset (MSBs for table selection)
*/
typedef 32'h00400000 DExIE_OFFSET_TABLES; // Bit 25...22 Dexie MSBs to select table

// Integer conversion
Integer wb_offset_imem_i = valueOf(WB_OFFSET_IMEM);
Integer wb_offset_dmem_i = valueOf(WB_OFFSET_DMEM);
Integer wb_offset_dex_mem_i = valueOf(WB_OFFSET_DEX_MEM);
Integer wb_offset_axi_ctrl_i = valueOf(WB_OFFSET_AXI_CTRL);
Integer dexie_offset_tables_i = valueOf(DExIE_OFFSET_TABLES);

Bit#(32) wb_offset_imem = fromInteger(wb_offset_imem_i);
Bit#(32) wb_offset_dmem = fromInteger(wb_offset_dmem_i);
Bit#(32) wb_offset_dex_mem = fromInteger(wb_offset_dex_mem_i);
Bit#(32) wb_offset_axi_ctrl = fromInteger(wb_offset_axi_ctrl_i);
Bit#(32) dexie_offset_tables = fromInteger(dexie_offset_tables_i);


/*
* Memory space configuration
* Byte amount for Macro and SPI
* Note: current implementation overlaps them, so first SPI bytes are
*       unusable since they are taken up by SRAM.
*       Reason: Still full memory map with failsafe disabling SRAM
*               and no change to default DExIE binary memory locations.
*/
typedef 32768 MACRO_SIZE;
typedef 'h20000 SPI_MEM_SIZE;

// How many GPIOs should the core be able to access.
typedef 10 NUM_GPIO_IN;
typedef 10 NUM_GPIO_OUT;

endpackage