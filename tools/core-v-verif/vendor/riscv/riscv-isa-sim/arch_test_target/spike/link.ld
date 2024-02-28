OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

SECTIONS
{
  . = 0x2000;
  .text.init : { *(.text.init) }
  .text : { *(.text) }
  . = 0x400000;
  .tohost : { *(.tohost) }
  .data : { *(.data) }
  .data.string : { *(.data.string)}
  .bss : { *(.bss) }
  _end = .;
}

