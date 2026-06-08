`include "cache_defs.vh"
module tag_array (
    input wire clk, input wire we, input wire [6:0] idx,
    input wire [19:0] wtag, input wire [1:0] wstate,
    output reg [19:0] rtag, output reg [1:0] rstate
);
    reg [19:0] tags [0:127];
    reg [1:0]  states [0:127];
    integer i;
    initial for(i=0; i<128; i=i+1) states[i] = `STATE_I;

    always @(posedge clk) begin
        if (we) begin
            tags[idx] <= wtag; states[idx] <= wstate;
            rtag <= wtag; rstate <= wstate;
        end else begin
            rtag <= tags[idx]; rstate <= states[idx];
        end
    end
endmodule
