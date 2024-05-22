package Config;

typedef 1 IFUINST;
typedef 1 ISSUEWIDTH;

typedef 0 RESETVEC;

/*
* Toplevel Wishbone Routing
* Caravel Userspace: 0x3000 0000 ... 0x7FFF FFFF
*  MSB 31==0, Block selection via MSBs 30...28
*  011 Scoooter IMEM
*  100 Scoooter DMEM
*  101 Free (?)
*  110 DExIE Tables
*  111 AXI CTRL
*
* Address range per Block; Bits 27...0 are freely usable
* 0...0xFFF FFFF = 0x1000 0000 combinations
* 0...268.435.455 = 268.435.455 combinations
* ca. 256 MByte per Block
*/

typedef 'b0011 WB_OFFSET_IMEM;
typedef 'b0100 WB_OFFSET_DMEM;
typedef 'b0101 WB_OFFSET_FREE;
typedef 'b0110 WB_OFFSET_DEX_MEM;
typedef 'b0111 WB_OFFSET_AXI_CTRL;

/*
* DExIE's Internal Table Offset (MSBs for table selection)
*/
typedef 'h1000000 DExIE_OFFSET_TABLES; // Bit 27...24 Dexie MSBs to select table

// Integer conversion
Integer wb_offset_imem_i = valueOf(WB_OFFSET_IMEM);
Integer wb_offset_dmem_i = valueOf(WB_OFFSET_DMEM);
Integer wb_offset_free_i = valueOf(WB_OFFSET_FREE);
Integer wb_offset_dex_mem_i = valueOf(WB_OFFSET_DEX_MEM);
Integer wb_offset_axi_ctrl_i = valueOf(WB_OFFSET_AXI_CTRL);
Integer dexie_offset_tables_i = valueOf(DExIE_OFFSET_TABLES);

Bit#(32) wb_offset_imem = fromInteger(wb_offset_imem_i);
Bit#(32) wb_offset_dmem = fromInteger(wb_offset_dmem_i);
Bit#(32) wb_offset_free = fromInteger(wb_offset_free_i);
Bit#(32) wb_offset_dex_mem = fromInteger(wb_offset_dex_mem_i);
Bit#(32) wb_offset_axi_ctrl = fromInteger(wb_offset_axi_ctrl_i);
Bit#(32) dexie_offset_tables = fromInteger(dexie_offset_tables_i);


/*
* Scoooter's internal memory offsets
*/
typedef 'h20000 BASE_DMEM;
typedef 'h20000 SIZE_DMEM;
typedef 'h00000 BASE_IMEM;
typedef 'h20000 SIZE_IMEM;

// must be at least as big as the issuewidth
typedef 1 ROB_BANK_DEPTH;

//must be at least as big as IFUINST and issuewidth
//and larger than 1 (required for MIMO)
typedef 2 INST_WINDOW;

// 0: single cycle
// 1: multi cycle
// 2: pipelined
typedef 1 MUL_DIV_STRATEGY;

// CSR and Mem units are always one
typedef 1 NUM_ALU;
typedef 1 NUM_MULDIV;
typedef 1 NUM_BR;

// Regfile as Latches
typedef 0 REGFILE_LATCH_BASED;
typedef 0 REGEVO_LATCH_BASED;
typedef 0 REGCSR_LATCH_BASED;

// rs depths
typedef 1 RS_DEPTH_ALU;
typedef 1 RS_DEPTH_MEM;
typedef 1 RS_DEPTH_CSR;
typedef 1 RS_DEPTH_MULDIV;
typedef 1 RS_DEPTH_BR;

// bus buffering
typedef 1 RS_LATCH_BUS;
typedef 1 DECODE_LATCH_OUTPUT;
typedef 1 ROB_LATCH_OUTPUT;
typedef 0 RESBUS_ADDED_DELAY;

// add more stages
typedef 0 RS_LATCH_INPUT;
typedef 0 SPLIT_ISSUE_STAGE;

// prediction strategy
// 0: always untaken
// 1: smiths
typedef 0 BRANCHPRED;

typedef 5 BITS_BTB;
typedef 5 BITS_PHT;

typedef 0 BITS_BHR;

typedef 0  USE_RAS;
typedef 1 RAS_SAVE_HEAD;
typedef 0 RAS_SAVE_FIRST;
typedef 16 RASDEPTH;

typedef 2 STORE_BUF_DEPTH;

typedef 1 NUM_CPU;
typedef 1 NUM_THREADS;
endpackage