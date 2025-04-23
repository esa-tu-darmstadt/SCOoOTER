###
# DO NOT CHANGE
###
TOP_MODULE=mkDave
TESTBENCH_MODULE=mkTestbench
IGNORE_MODULES=mkTestbench mkTestsMainTest
MAIN_MODULE=src_core/Dave
TESTBENCH_FILE=src/src_test/Testbench.bsv

ifeq ($(SOC), 1)
	TOP_MODULE=mkSocTop
	TESTBENCH_MODULE=mkSocTop
	MAIN_MODULE=src_soc/SocTop
	TESTBENCH_FILE=src/src_soc/SocTop.bsv
endif

ifeq ($(CARAVEL), 1)
	TOP_MODULE=mkScoooterCaravel
	TESTBENCH_MODULE=mkScoooterCaravel
	MAIN_MODULE=src_openlane/SoC_WB
	TESTBENCH_FILE=src/src_openlane/SoC_WB.bsv
endif

ifeq ($(CARAVEL_SIM), 1)
	TOP_MODULE=mkSoC
	TESTBENCH_MODULE=mkTestSoC
	MAIN_MODULE=src_openlane/SoC_AXI
	TESTBENCH_FILE=src/src_openlane/TestSoC_AXI.bsv
	TB=CUSTOM_TB
endif

# Sizes for internal memory map if needed
TAPASCO_BRAM_SIZE ?= 0x20000
TAPASCO_BRAM_SIZE_BSV := $(shell echo $(TAPASCO_BRAM_SIZE) | sed -r "s/0x/'h/g")

# Initialize
-include .bsv_tools
ifndef BSV_TOOLS
$(error BSV_TOOLS is not set (Check .bsv_tools or specify it through the command line))
endif
VIVADO_ADD_PARAMS := ''
CONSTRAINT_FILES := ''
EXTRA_BSV_LIBS:=
EXTRA_LIBRARIES:=
RUN_FLAGS:=

TB?=ISA_TB
BRANCH?=0
# 1: build frontend, exec and backend separately
# 2: build all modules separately
SYNTH?=0
LOG?=0
RVFI?=0
TOHOST?=0

# Add subdirectories
EXTRA_BSV_LIBS += $(shell find $(CURDIR)/src/* -type d -printf '%p ')

PROJECT_NAME=SCOOOTER_riscv

ifeq ($(RUN_TEST),)
RUN_TEST=TestsMainTest
endif
# Default flags
#EXTRA_FLAGS= -D "TAPASCO_BRAM_SIZE=$(TAPASCO_BRAM_SIZE_BSV)"
EXTRA_FLAGS+= -D "RUN_TEST=$(RUN_TEST)" -D "TESTNAME=mk$(RUN_TEST)" -steps-max-intervals 5000000
EXTRA_FLAGS+= -show-schedule -D "BSV_TIMESCALE=1ns/1ps"
EXTRA_FLAGS+= -D $(TB) +RTS -K1G -RTS -D BSV_ASYNC_RESET -D TOHOST=$(TOHOST)

ifeq ($(SOC),)
	ifeq ($(SIM_TYPE),)
		EXTRA_FLAGS+=  -keep-fires -D BSV_NO_INITIAL_BLOCKS
	endif
else
		EXTRA_FLAGS+= -D SOC
endif
ifeq ($(IP),1)
EXTRA_FLAGS+= -lift -aggressive-conditions -opt-undetermined-vals -verilog-filter "sed -i \"/\/\/ synopsys translate_off/,/\/\/ synopsys translate_on/d\" " -D BSV_NO_INITIAL_BLOCKS
else
EXTRA_FLAGS+= -parallel-sim-link 48
endif


ifeq ($(SYNTH),1)
	EXTRA_FLAGS+=-D SYNTH_SEPARATE_BLOCKS
endif
ifeq ($(SYNTH),2)
	EXTRA_FLAGS+=-D SYNTH_SEPARATE_BLOCKS -D SYNTH_SEPARATE
endif
ifeq ($(LOG),1)
	EXTRA_FLAGS+=-D LOG_PIPELINE
endif
ifeq ($(BRANCH),1)
	EXTRA_FLAGS+=-D EVA_BR
endif
ifeq ($(RVFI),1)
	EXTRA_FLAGS+=-D RVFI
endif
ifeq ($(DEXIE),1)
	EXTRA_FLAGS+=-D DEXIE
endif
ifeq ($(EFSRAM),1)
	EXTRA_FLAGS+=-D EFSRAM
endif

$(shell cp src/BVI/*.v build/verilog)

###
# User configuration
###

# Comment the following line if -O3 should be used during compilation
# Keep uncommented for short running simulations
CXX_NO_OPT := 1

# Any additional files added during compilation
# For instance for BDPI or Verilog/VHDL files for simulation
# CPP_FILES += $(current_dir)/src/mem_sim.cpp

# Custom defines added to compile steps
# EXTRA_FLAGS+=-D "BENCHMARK=1"

# Flags added to simulator execution
# RUN_FLAGS+=-V dump.vcd

# Add additional parameters for IP-XACT generation. Passed directly to Vivado.
# Any valid TCL during packaging is allowed
# Typically used to fix automatic inference for e.g. clock assignments
# VIVADO_ADD_PARAMS += 'ipx::associate_bus_interfaces -busif M_AXI -clock sconfig_axi_aclk [ipx::current_core]'

# Add custom constraint files, Syntax: Filename,Load Order
# CONSTRAINT_FILES += "$(PWD)/constraints/custom.xdc,LATE"

# Do not change: Load libraries such as BlueAXI or BlueLib
ifneq ("$(wildcard $(CURDIR)/libraries/*/*.mk)", "")
include $(CURDIR)/libraries/*/*.mk
endif

# Do not change: Include base makefile
include $(BSV_TOOLS)/scripts/rules.mk
