# Testbenches

This folder contains SCOoOTERs testbenches.
`TestbenchProgram` executes a test program on a single DUT.
`TestsMulti` instantiates multiple program testbenches to execute test suites in parallel. It contains job lists for the SCOoOTER-supported test suites.
`Testbench` is the toplevel testbench that instantiates either a program or multi testbench depending on the selected test.

`RamSim` simulates a 8-Bit MRAM external memory and is currently used for further development.