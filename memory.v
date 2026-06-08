`include "cache_defs.vh"

module memory (
    input  wire clk,
    input  wire rst,
    // Read Port
    input  wire mem_rd,
    input  wire [31:0] mem_addr,
    output reg [255:0] mem_data,
    output reg  mem_vld,
    // Write Port (For Write-Back)
    input  wire mem_wr,
    input  wire [31:0] wr_addr,
    input  wire [255:0] wr_data,
    output reg  wr_done
);
    // Use localparams as a backup if macros fail
    localparam MEM_SIZE = 1024; 
    reg [255:0] mem_array [0:MEM_SIZE-1];

    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            mem_array[i] = {8{32'hDEADBEEF}}; // Default pattern
        end
    end

    // Memory Logic
    always @(posedge clk) begin
        if (rst) begin
            mem_vld <= 0;
            wr_done <= 0;
        end else begin
            // Handle Reads
            if (mem_rd) begin
                mem_data <= mem_array[mem_addr[14:5]]; // Simplified indexing
                mem_vld  <= 1;
            end else begin
                mem_vld  <= 0;
            end

            // Handle Writes (Write-back)
            if (mem_wr) begin
                mem_array[wr_addr[14:5]] <= wr_data;
                wr_done <= 1;
            end else begin
                wr_done <= 0;
            end
        end
    end
endmodule
