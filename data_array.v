// data_array.v
`include "cache_defs.vh"

module data_array (
    input  wire clk,
    input  wire we,
    input  wire [`INDEX_BITS-1:0] idx,
    input  wire [`LINE_SIZE-1:0] wline,
    output reg  [`LINE_SIZE-1:0] rline
);

    localparam NUM_SETS = `NUM_SETS;
    localparam LINE_SIZE = `LINE_SIZE;

    reg [LINE_SIZE-1:0] mem [0:NUM_SETS-1];

    integer i;
    initial begin
        for (i = 0; i < NUM_SETS; i = i + 1)
            mem[i] = {LINE_SIZE{1'b0}};
    end

    always @(posedge clk) begin
        if (we) begin
            mem[idx] <= wline;
            rline <= wline;
        end else begin
            rline <= mem[idx];
        end
    end

endmodule
