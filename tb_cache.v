// tb_cache.v
`timescale 1ns/1ps
`include "cache_defs.vh"

module tb_cache;

    reg clk = 0;
    reg rst = 1;

    always #5 clk = ~clk;

    reg  cpu_req_valid;
    reg  cpu_req_rw;
    reg  [`ADDR_WIDTH-1:0] cpu_addr;
    reg  [`DATA_WIDTH-1:0] cpu_wdata;
    wire cpu_req_ready;
    wire cpu_resp_valid;
    wire [`DATA_WIDTH-1:0] cpu_rdata;

    wire mem_rd_req;
    wire [`ADDR_WIDTH-1:0] mem_rd_addr;
    wire mem_rd_resp_valid;
    wire [`LINE_SIZE-1:0] mem_rd_line;

    wire mem_wb_req;
    wire [`ADDR_WIDTH-1:0] mem_wb_addr;
    wire [`LINE_SIZE-1:0] mem_wb_line;
    wire mem_wb_done;

    // Instantiate cache
    cache_core dut (
        .clk(clk), .rst(rst),
        .cpu_req_valid(cpu_req_valid),
        .cpu_req_rw(cpu_req_rw),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_req_ready(cpu_req_ready),
        .cpu_resp_valid(cpu_resp_valid),
        .cpu_rdata(cpu_rdata),
        .mem_rd_req(mem_rd_req),
        .mem_rd_addr(mem_rd_addr),
        .mem_rd_resp_valid(mem_rd_resp_valid),
        .mem_rd_line(mem_rd_line),
        .mem_wb_req(mem_wb_req),
        .mem_wb_addr(mem_wb_addr),
        .mem_wb_line(mem_wb_line),
        .mem_wb_done(mem_wb_done)
    );

    // Instantiate memory
    memory mem (
        .clk(clk), .rst(rst),
        .rd_req(mem_rd_req),
        .rd_addr(mem_rd_addr),
        .rd_resp_valid(mem_rd_resp_valid),
        .rd_line(mem_rd_line),
        .wb_req(mem_wb_req),
        .wb_addr(mem_wb_addr),
        .wb_line(mem_wb_line),
        .wb_done(mem_wb_done)
    );

    // Tasks for read/write
    task read(input [`ADDR_WIDTH-1:0] addr);
        begin
            @(posedge clk);
            cpu_req_valid = 1'b1;
            cpu_req_rw = 1'b0;
            cpu_addr = addr;
            cpu_wdata = {`DATA_WIDTH{1'b0}};
            wait(cpu_req_ready);
            @(posedge clk);
            cpu_req_valid = 1'b0;
            wait(cpu_resp_valid);
            @(posedge clk);
            $display("[%0t] READ  @%08h -> %016h", $time, addr, cpu_rdata);
        end
    endtask

    task write(input [`ADDR_WIDTH-1:0] addr, input [`DATA_WIDTH-1:0] data);
        begin
            @(posedge clk);
            cpu_req_valid = 1'b1;
            cpu_req_rw = 1'b1;
            cpu_addr = addr;
            cpu_wdata = data;
            wait(cpu_req_ready);
            @(posedge clk);
            cpu_req_valid = 1'b0;
            wait(cpu_resp_valid);
            @(posedge clk);
            $display("[%0t] WRITE @%08h := %016h", $time, addr, data);
        end
    endtask

    initial begin
        $dumpfile("cache.vcd");
        $dumpvars(0, tb_cache);

        // Reset
        rst = 1;
        cpu_req_valid = 0;
        #20 rst = 0;
        #10;

        // Test 1: Read miss at 0x0040
        $display("Test 1: Read miss at 0x40");
        read(32'h0000_0040);

        // Test 2: Read hit
        $display("Test 2: Read hit at 0x40");
        read(32'h0000_0040);

        // Test 3: Write hit
        $display("Test 3: Write hit at 0x40");
        write(32'h0000_0040, 64'hDEADBEEF_12345678);

        // Test 4: Read after write
        $display("Test 4: Read after write");
        read(32'h0000_0040);

        // Test 5: Write to different line in same set (0x1040) to cause eviction
        $display("Test 5: Write to 0x1040 (same set)");
        write(32'h0000_1040, 64'hFFFF_FFFF_FFFF_FFFF);

        // Test 6: Read 0x0040 again – should miss and reload
        $display("Test 6: Read 0x0040 again");
        read(32'h0000_0040);

        // Test 7: Read 0x1040
        $display("Test 7: Read 0x1040");
        read(32'h0000_1040);

        #50 $finish;
    end

endmodule
