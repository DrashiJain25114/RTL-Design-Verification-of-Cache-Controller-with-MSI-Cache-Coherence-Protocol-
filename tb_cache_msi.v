`timescale 1ns/1ps
`include "cache_defs.vh"

module tb_cache_msi;
    reg clk=0; reg rst=1;
    always #5 clk = ~clk;

    // CPU 0 & 1 Signals
    reg c0_valid, c0_rw, c1_valid, c1_rw;
    reg [31:0] c0_addr, c1_addr;
    reg [63:0] c0_wdata, c1_wdata;
    wire c0_resp, c1_resp;
    wire [63:0] c0_rdata, c1_rdata;

    // Bus Signals
    wire [1:0] bus_cmd; wire [31:0] bus_addr; wire [255:0] bus_data;
    wire c0_grant, c1_grant, c0_hit_m, c1_hit_m, bus_vld;
    wire [255:0] c0_data_out, c1_data_out;
    wire [1:0] c0_bus_req, c1_bus_req;
    wire [31:0] c0_bus_addr, c1_bus_addr;

    bus_arbiter bus_inst (.clk(clk), .c0_req(c0_bus_req), .c0_addr(c0_bus_addr), .c0_grant(c0_grant), .c0_hit_m(c0_hit_m), .c0_data_in(c0_data_out),
                         .c1_req(c1_bus_req), .c1_addr(c1_bus_addr), .c1_grant(c1_grant), .c1_hit_m(c1_hit_m), .c1_data_in(c1_data_out),
                         .bus_cmd(bus_cmd), .bus_addr(bus_addr), .bus_data(bus_data), .bus_data_vld(bus_vld), .mem_rd(), .mem_data(256'hCAFE_BABE_DEAD_BEEF));

    cache_core core0 (.clk(clk), .rst(rst), .cpu_req_valid(c0_valid), .cpu_req_rw(c0_rw), .cpu_addr(c0_addr), .cpu_wdata(c0_wdata), .cpu_resp_valid(c0_resp), .cpu_rdata(c0_rdata),
                     .bus_req_out(c0_bus_req), .bus_addr_out(c0_bus_addr), .bus_cmd_in(bus_cmd), .bus_addr_in(bus_addr), .bus_grant(c0_grant), .bus_data_vld(bus_vld), .bus_data_in(bus_data), .bus_data_out(c0_data_out), .snoop_hit_m(c0_hit_m), .mem_wb_done(1'b1));

    cache_core core1 (.clk(clk), .rst(rst), .cpu_req_valid(c1_valid), .cpu_req_rw(c1_rw), .cpu_addr(c1_addr), .cpu_wdata(c1_wdata), .cpu_resp_valid(c1_resp), .cpu_rdata(c1_rdata),
                     .bus_req_out(c1_bus_req), .bus_addr_out(c1_bus_addr), .bus_cmd_in(bus_cmd), .bus_addr_in(bus_addr), .bus_grant(c1_grant), .bus_data_vld(bus_vld), .bus_data_in(bus_data), .bus_data_out(c1_data_out), .snoop_hit_m(c1_hit_m), .mem_wb_done(1'b1));

    initial begin
        $dumpfile("msi_final.vcd"); $dumpvars(0, tb_cache_msi);
        rst = 1; #20 rst = 0;
        
        $display("--- SCENARIO 1: SHARED READ (C0 then C1) ---");
        c0_read(32'h100);
        c1_read(32'h100);
        
        $display("--- SCENARIO 2: UPGRADE (C0 Writes to Shared Line) ---");
        c0_write(32'h100, 64'hFACE_B00C_DEAD_BEEF);
        // Verify C1 is now Invalid

        $display("--- SCENARIO 3: INTERVENTION (C1 reads M line from C0) ---");
        c1_read(32'h100);
        if (c1_rdata == 64'hFACE_B00C_DEAD_BEEF) $display("PASS: Core 1 got data from Core 0!");

        $display("--- SCENARIO 4: WRITE-BACK & REPLACEMENT ---");
        // Access 3 unique addresses at the same index to force Core 1 way-eviction
        c1_read(32'h200);
        c1_read(32'h300); 

        $display("--- SCENARIO 5: SIMULTANEOUS REQUESTS ---");
        fork
            c0_write(32'h400, 64'h1111);
            c1_write(32'h500, 64'h2222);
        join

        #100 $display("ALL COHERENCE SCENARIOS COMPLETE."); $finish;
    end

    // Helper Tasks
    task c0_write(input [31:0] addr, input [63:0] data);
        begin c0_valid = 1; c0_rw = 1; c0_addr = addr; c0_wdata = data;
        wait(c0_resp); @(posedge clk) c0_valid = 0; end
    endtask

    task c0_read(input [31:0] addr);
        begin c0_valid = 1; c0_rw = 0; c0_addr = addr;
        wait(c0_resp); @(posedge clk) c0_valid = 0; end
    endtask

    task c1_read(input [31:0] addr);
        begin c1_valid = 1; c1_rw = 0; c1_addr = addr;
        wait(c1_resp); @(posedge clk) c1_valid = 0; end
    endtask

    task c1_write(input [31:0] addr, input [63:0] data);
        begin c1_valid = 1; c1_rw = 1; c1_addr = addr; c1_wdata = data;
        wait(c1_resp); @(posedge clk) c1_valid = 0; end
    endtask

endmodule
