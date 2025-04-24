# Primitives

This folder contains library components used as replacements for BSV standard library components or in multiple places of SCOoOTER.

`Ehr` is an alternative CReg implementation with less constraints on the port number, scheduling, and a different interface.
`ArianeEhr` provides an `Ehr` implementation based on latches.
`BuildList` provides list functions similar to BSVs `BuildVector` vector functions.
`CWire` provides an `Ehr`-like functionality without preserving data between cycles.
`ESAMIMO` provides a BSV-like MIMO implementation that is more efficient for our use-case.
`GetPutCustom` extend the BSV GetPut interfaces with information on a possible dequeue/enqueue amount.
`ShiftBuffer` is a module for delaying signals for a pre-set number of cycles.
`TestFunctions` contains generic functions for extracting elements from vectors, tests on vectors, tests on data, and bounded addition operations.