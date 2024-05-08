
# Quickstart

This documentation file introduces SCOoOTERs environment setup and basic first steps.

## Prerequisites

SCOoOTER requires the following tools for compilation and simulation:

- bsc, the Bluespec compiler (and its dependencies)
- Python 3.x
- Vivado (for IP core building)
- [BSVTools](https://github.com/esa-tu-darmstadt/BSVTools)

Building and executing the tests additionally requires the following tools:

- A RISCV32 compiler and binutils
- Questa (for dynamic test generation)
- Cocotb

Generating logs for the pipeline viewer requires:

- Spike-dasm, a disassembler distributed with the Spike ISS

## Initializing the environment

First, clone the SCOoOTER repository while recursing submodules:

```
git clone git@gitlab.esa.informatik.tu-darmstadt.de:risc-v/scoooter.git -r
```

Add the project to your BSVTools instance. Alternatively, the test case build script clones and setups BSVTools for you. Test cases can be built using:

```
./build_test_programs.sh
```

## Changing the configuration

The config file is located in `core/src/Config.bsv`. The parameters are described by comments in the file.

Configuration files for the default tests are located in the `testConfigs` directory. `high`, `medium` and `simple` refer to three configurations of SCOoOTER with different amounts of features enabled. Configs ending with `cv` are used for Core-V-Verif tests. `multihart-isa` is used for parallel reduction tests and `multihart-random` is used for the LRSC stress test. Refer to the next section for how to execute those tests. `nopred`, `smiths`, `gshare` and `gskewed` refer to the branch predictor used.

## Executing tests

Simple tests as well as custom programs can be executed directly using BlueSim, the Bluespec SystemVerilog simulator. Tests are selected by an environment variable. Make must be executed within the `core` directory.

```
make TB=XYZ_TB
```

Following tests are available:

- CUSTOM_TB:  Run a custom test program as defined in Testbench.bsv
- ISA_TB:     Run the RISC-V ISA tests
- PRIV_TB:    Run the RISC_V arch tests for privileged operations
- AMO_TB:     Run parallel reduction tests on multiple threads/cores
- LRSC_TB:    Execute LRSC stress test
- RVFI_TB:    Execute program in the `program/` folder and write RVFI trace. Used for Core-V-Verif TB
- Embench_TB: Run Embench-IoT

Complex random-generated tests may be generated through Core-V-Verif. Default test cases may be executed by SOURCING the following script:

```
source ./run_core_v
```

## Building IP cores

IP cores are built through BSVTools. When building hardware for synthesis, we should disable generation of debug-code. This can be done by setting the IP environment variable during build.

```
make SIM_TYPE=VERILOG ip IP=1
```

As described in the BSVTools documentation, we must set the simulation type to Verilog such that .v files are produced.

## More simulation options

More options may be passed to make through environment variables.

- SYNTH:  Set this to 1 if you want to get separate verilog-modules for the frontend, execution core and backend.  Set this to 2 if you want to synthesize every module separately.
- LOG:    Set this to 1 if you want to log the instructions passing through the pipeline. A graphical log for Konata as well as a log for our custom terminal-based pipeline viewer is generated.
- BRANCH: Set this to 1 to get information on the amount of correct and wrongly predicted branches.
- RVFI:   Set this to 1 to get an RVFI trace (mainly used for Core-V-Verif). RVFI is only implemented to the extend required by Core-V-Verif.
- DEXIE:  Generate ports for DExIE. This is used for dynamic control flow integrity protection in hardware.