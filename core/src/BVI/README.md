# BVI - Bluespec Verilog Interface

This folder contains Verilog files which have been wrapped for Bluespec use.

Currently, this includes latche-based register files for SCOoOTER, which can be selected as an alternative to the flipflop-based one.
Since Bluespec does not allow for latch creation, those modules are written in Verilog. They have been copied from Ariane / CVA6.
`ariane_reg` is a single latch, `regfile_ariane_lol` is a RISC-V compliant register file with 31 registers and address 0 always returning 0.