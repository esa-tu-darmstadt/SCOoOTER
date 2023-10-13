###
# DO NOT CHANGE
###
TOP_MODULE=mkDave
TESTBENCH_MODULE=mkTestbench
IGNORE_MODULES=mkTestbench mkTestsMainTest
MAIN_MODULE=src_core/Dave
TESTBENCH_FILE=src/src_test/Testbench.bsv

ifeq ($(SOC), 1)
	TOP_MODULE=mkExecCore
	MAIN_MODULE=src_core/exec_core/ExecCore
endif

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
EXTRA_BSV_LIBS += $(shell find $(PWD)/src/* -type d -printf '%p ')

PROJECT_NAME=SCOOOTER_riscv

ifeq ($(RUN_TEST),)
RUN_TEST=TestsMainTest
endif

# Default flags
EXTRA_FLAGS= -D "RUN_TEST=$(RUN_TEST)" -D "TESTNAME=mk$(RUN_TEST)" -steps-max-intervals 5000000
EXTRA_FLAGS+= -show-schedule -D "BSV_TIMESCALE=1ns/1ps -keep-fires"
EXTRA_FLAGS+= -D $(TB) -D BSV_NO_INITIAL_BLOCKS +RTS -K1G -RTS -D BSV_ASYNC_RESET -D TOHOST=$(TOHOST)
EXTRA_FLAGS+= -verilog-filter "sed -i \"/\/\/ synopsys translate_off/,/\/\/ synopsys translate_on/d\" "

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
ifneq ("$(wildcard $(PWD)/libraries/*/*.mk)", "")
include $(PWD)/libraries/*/*.mk
endif

# Do not change: Include base makefile
include $(BSV_TOOLS)/scripts/rules.mk
