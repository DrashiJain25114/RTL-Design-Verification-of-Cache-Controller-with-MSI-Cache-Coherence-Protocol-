`include "cache_defs.vh"

module bus_arbiter (
    input wire clk,
    // Core 0
    input wire [1:0] c0_req, input wire [31:0] c0_addr, output reg c0_grant,
    input wire c0_hit_m, input wire [255:0] c0_data_in,
    // Core 1
    input wire [1:0] c1_req, input wire [31:0] c1_addr, output reg c1_grant,
    input wire c1_hit_m, input wire [255:0] c1_data_in,
    
    // Global Bus
    output reg [1:0] bus_cmd, output reg [31:0] bus_addr, 
    output reg [255:0] bus_data, output reg bus_data_vld,
    output reg mem_rd, input wire [255:0] mem_data
);

    reg [1:0] arb_state; // Fixed: 2-bit register
    localparam ARB_IDLE = 2'd0, ARB_DATA = 2'd1;

    always @(posedge clk) begin
        bus_data_vld <= 0;
        mem_rd <= 0;

        case (arb_state)
            ARB_IDLE: begin
                if (c0_req != `BUS_IDLE) begin
                    c0_grant <= 1; c1_grant <= 0;
                    bus_cmd <= c0_req; bus_addr <= c0_addr;
                    arb_state <= ARB_DATA;
                end else if (c1_req != `BUS_IDLE) begin
                    c1_grant <= 1; c0_grant <= 0;
                    bus_cmd <= c1_req; bus_addr <= c1_addr;
                    arb_state <= ARB_DATA;
                end else begin
                    c0_grant <= 0; c1_grant <= 0;
                    bus_cmd <= `BUS_IDLE;
                end
            end

            ARB_DATA: begin
                // Drive Data Phase
                if (c0_grant && c1_hit_m) bus_data <= c1_data_in;
                else if (c1_grant && c0_hit_m) bus_data <= c0_data_in; 
                else begin
                    mem_rd <= 1;
                    bus_data <= mem_data;
                end
                
                bus_data_vld <= 1;
                arb_state <= ARB_IDLE;
            end
            default: arb_state <= ARB_IDLE;
        endcase
    end
endmodule
