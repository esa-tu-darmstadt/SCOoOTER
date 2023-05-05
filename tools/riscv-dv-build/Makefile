# Makefile implementing top level verification behaviour
ABI = ilp32

QUESTA_HOME := /opt/cad/mentor/2020-21/RHELx86/QUESTA-CORE-PRIME_2020.4/questasim



# Taken and adapted from pyuvm/examples/TinyALU/Makefile
PWD=$(shell pwd)
COCOTB_REDUCED_LOG_FMT = False
SIM ?= questa
TOPLEVEL_LANG ?= verilog
CORE_TOP ?= mkDave
TOPLEVEL = $(CORE_TOP)

HDL_PATH = $(PWD)/../../core/build/ip/SCOOOTER_riscv/src
ifeq ($(TOPLEVEL_LANG),verilog)
    VERILOG_SOURCES=$(HDL_PATH)/$(CORE_TOP).v $(HDL_PATH)/FIFOL1.v $(HDL_PATH)/SizedFIFO.v $(HDL_PATH)/RevertReg.v $(HDL_PATH)/mkSCOOOTER_riscv.v $(HDL_PATH)/mkDave.v $(HDL_PATH)/mkInstructionArbiter.v $(HDL_PATH)/mkMemoryArbiter.v
else ifeq ($(TOPLEVEL_LANG),vhdl)
	VHDL_SOURCES=$(CWD)/../core_rtl/$(CORE_TOP).vhd
else
    $(error "A valid value (verilog or vhdl) was not provided for TOPLEVEL_LANG=$(TOPLEVEL_LANG)")
endif

MODULE := dv_tests
COCOTB_HDL_TIMEUNIT = 1us
COCOTB_HDL_TIMEPRECISION = 1us
RUN_ARGS=-noautoldlibpath
include $(shell cocotb-config --makefiles)/Makefile.sim
RISCV_DV := $(PWD)/../riscv-dv


ifndef RISCV_DV
$(error RISCV_DV is not set. Set it to the riscv-dv root folder.)
endif

gen_stimulus: prep_stimulus
	cd riscv-dv-extension && RISCV_GCC=riscv64-unknown-elf-gcc \
	RISCV_OBJCOPY=riscv64-unknown-elf-objcopy \
	QUESTA_HOME=/opt/cad/mentor/2020-21/RHELx86/QUESTA-CORE-PRIME_2020.4/questasim \
	run -ct $(PWD)/riscv-dv-extension/scoooter-amo/ \
	--simulator=questa --isa rv32ima --mabi $(ABI) --steps gen,gcc_compile \
	-ext $(PWD)/riscv-dv-extension/sv/ \
	--sim_opts="+uvm_set_inst_override=riscv_asm_program_gen,riscv_no_csr_asm_program_gen,'uvm_test_top.asm_gen'" -o rv32_tests

# Move own link.ld to riscv-dv and secure the old linker script as link_orig.ld
prep_stimulus:
	#mv $(RISCV_DV)/scripts/link.ld $(RISCV_DV)/scripts/link_orig.ld
	cp riscv-dv-extension/link.ld $(RISCV_DV)/scripts/link.ld
	#touch prep_stimulus
	

collect: gen_stimulus
	mkdir -p out/elf
	cp riscv-dv-extension/rv32_tests/asm_test/*.o out/elf/
	mkdir -p out/dump_asm
	cp riscv-dv-extension/rv32_tests/asm_test/*.S out/dump_asm/
	mkdir -p out/bin
	cp riscv-dv-extension/rv32_tests/asm_test/*.bin out/bin/

transform: collect
	#copy all binaries over
	@$(eval ELFS:=$(wildcard out/elf/*))
	@$(eval ELFS_SHORT := $(basename $(notdir ${ELFS})))

	#make BSV hex from verilog
	@mkdir -p out/bsv_hex
	@$(foreach bin, ${ELFS_SHORT}, python3 ../hexConverter/hexConverter.py out/bin/$(bin).bin -o out/bsv_hex/$(bin) -b 0x40000 ; )
	
	#make dump from ELF files
	@mkdir -p out/dump
	@$(foreach bin, ${ELFS_SHORT}, riscv64-unknown-elf-objdump -d out/elf/$(bin).o > out/dump/$(bin).dump ; )

install: transform
	@mkdir -p ../../testPrograms/amo
	@cp -r out/* ../../testPrograms/amo
