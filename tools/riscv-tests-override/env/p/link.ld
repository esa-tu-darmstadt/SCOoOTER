OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text.init : { *(.text.init) }
  .tohost : { *(.tohost) }
  .text : { *(.text) }
  . = 0x10000;
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
}

