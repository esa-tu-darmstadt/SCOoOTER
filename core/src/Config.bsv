package Config;


// This is SCOoOTERs main configuration file
// Here, you can change architectural decisions


// Set the number of instructions fetched per cycle
// This modifies the width of the fetch bus
// Make sure to set this to at least the ISSUEWIDTH to avoid bottlenecking
typedef 1 IFUINST;
// Set the number of instructions issued per cycle
// This widens the issue logic and also increases the width of the commit stage
typedef 1 ISSUEWIDTH;

// Initial program counter
// Address of the first instruction to execute
typedef 0 RESETVEC;

// Memory region for instructions
typedef 'h00000 BASE_IMEM;
typedef 'h10000 SIZE_IMEM;

// Memory region for data memory
// Speculative reads are allowed inside this region as a performance improvement
typedef 'h10000 BASE_DMEM;
typedef 'h10000 SIZE_DMEM;

// Size of the Reorder Buffer banks
// The reorder buffer is banked to allow for multi-issue
// This setting increases the size per bank
// So the ROB has a capacity of ROB_BANK_DEPTH*ISSUEWIDTH
typedef 8 ROB_BANK_DEPTH;

// Size of the buffer between the frontend and execution core
// holds fetched instructions before they are issued
// must be at least as big as IFUINST and ISSUEWIDTH
// since the fetch stage might enqueue IFUINST entries
// and the issue stage might dequeue ISSUEWIDTH entries
// and larger than 1 (required for BSV MIMO modules)
typedef 4 INST_WINDOW;

// Implementation strategy for multiply / divide
// Ranges from naive to sophisticated
// Influences fmax, area and performance significantly
// 0: single cycle - use Verilog operator
// 1: multi cycle - FSM-based implementation over multiple cycles
// 2: pipelined - fully pipelined, operation can be started on any cycle
typedef 2 MUL_DIV_STRATEGY;

// Mix of functional units for instruction execution
// The number of CSR and MEM units is always 1 since the state components only have a single bus
// Other execution units can be freely configured
// More FUs can increase parallelism but also enlarge the issue stage complexity
// At some point, the fmax hit by the increased issue complexity diminishes performance gains
// If no MulDiv units are enabled, the RISC-V M extension is disabled
typedef 1 NUM_ALU;
typedef 1 NUM_MULDIV;
typedef 1 NUM_BR;

// Implement registers as latches
// Latch-based implementations require less area and may be favoured on ASIC
// The architectural registers (REGFILE), speculative registers (REGEVO) and CSRs (REGCSR) may be implemented using latches
// 0: registers - 1: latches
typedef 0 REGFILE_LATCH_BASED;
typedef 0 REGEVO_LATCH_BASED;
typedef 0 REGCSR_LATCH_BASED;

// Depths of the ReservationStation
// How many instructions each reservation station for a given fu type can hold
typedef 2 RS_DEPTH_ALU;
typedef 2 RS_DEPTH_MEM;
typedef 2 RS_DEPTH_CSR;
typedef 2 RS_DEPTH_MULDIV;
typedef 2 RS_DEPTH_BR;

// Amount of store buffer entries
// The store buffer holds write requests to memory until they are committed via the bus
// And allows forwarding from them
// Currently, only pwr2 sizes are allowed
typedef 8 STORE_BUF_DEPTH;

// BRANCH PREDICTOR SETTINGS

// branch direction prediction strategy
// selects the implementation
// 0: always untaken
// 1: smiths
// 2: gshare
// 3: gskewed
typedef 2 BRANCHPRED;

// bits of the PC used for indexing the Branch Target Buffer or Direction Predictor
// also determines the size of those buffers
typedef 5 BITS_BTB; // branch target buffer index size, set to 0 to disable BTB
typedef 5 BITS_PHT; // direction predictor index size

// size of the branch history register
// only relevant for gshare and gskewed
typedef 3 BITS_BHR; 

// use a return address stack
// 0: enabled - 1: disabled
typedef 1 USE_RAS;
// RAS misprediction recovary strategy
// 0: enabled - 1: disabled
typedef 0 RAS_SAVE_HEAD;
typedef 0 RAS_SAVE_FIRST;
// size of the RAS
typedef 2 RASDEPTH;

// Multithread options

typedef 1 NUM_THREADS; // number of threads per CPU
typedef 1 NUM_CPU; // number of CPUs

// ADVANCED OPTIONS

// Optionally, add more stages to the pipeline
// 0: disabled - 1: enabled
// add a stage after decode to sort instructions into the instruction window
typedef 0 DECODE_LATCH_OUTPUT;
// add a stage after the ROB to decouple the commit logic and dequeue from ROB
typedef 0 ROB_LATCH_OUTPUT;
// add registers to buffer the result bus
// results need an additional cycle to reach RSs but timing can be improved
typedef 0 RESBUS_ADDED_DELAY;
// add a dedicated enqueue cycle for instructions entering an RS
typedef 0 RS_LATCH_INPUT;
// split the issue stage into two stages
typedef 0 SPLIT_ISSUE_STAGE;
endpackage
