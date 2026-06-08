`ifndef CACHE_DEFS_VH
`define CACHE_DEFS_VH

`define ADDR_WIDTH 32
`define DATA_WIDTH 64
`define LINE_SIZE   256
`define NUM_SETS    128
`define INDEX_BITS  7
`define TAG_BITS    20

// MSI States
`define STATE_I 2'b00
`define STATE_S 2'b01
`define STATE_M 2'b10

// Bus Commands
`define BUS_IDLE 2'b00
`define BUS_RD   2'b01  // Read (Get Shared)
`define BUS_RDX  2'b10  // Read Exclusive (Get Modified/Invalidate)
`define BUS_UPGR 2'b11  // Upgrade (S -> M)

`endif
