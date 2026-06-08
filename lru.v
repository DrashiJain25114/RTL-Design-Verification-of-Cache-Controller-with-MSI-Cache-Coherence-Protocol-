`include "cache_defs.vh"

module lru (
    input wire clk,
    input wire rst,
    input wire [6:0] idx,
    input wire hit0,
    input wire hit1,
    output wire victim
);
    // 128 bits to track which way was Least Recently Used for each set
    // bit = 0: Way 0 is LRU (Victim)
    // bit = 1: Way 1 is LRU (Victim)
    reg [127:0] lru_bits;

    always @(posedge clk) begin
        if (rst) begin
            lru_bits <= 128'b0;
        end else begin
            // If we hit Way 0, Way 1 becomes the next victim
            if (hit0)      lru_bits[idx] <= 1'b1;
            // If we hit Way 1, Way 0 becomes the next victim
            else if (hit1) lru_bits[idx] <= 1'b0;
        end
    end

    // Output the victim bit for the current index
    assign victim = lru_bits[idx];

endmodule
