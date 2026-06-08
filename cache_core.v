`include "cache_defs.vh"

module cache_core (
    input  wire clk, input  wire rst,
    input  wire cpu_req_valid, input  wire cpu_req_rw,
    input  wire [31:0] cpu_addr, input  wire [63:0] cpu_wdata,
    output reg  cpu_req_ready, output reg  cpu_resp_valid, output reg [63:0] cpu_rdata,
    input  wire [1:0]  bus_cmd_in, input  wire [31:0] bus_addr_in,
    output reg [1:0]   bus_req_out, output reg [31:0] bus_addr_out,
    input  wire        bus_grant, input  wire bus_data_vld,
    input  wire [255:0] bus_data_in, output wire [255:0] bus_data_out,
    output reg         snoop_hit_m,
    output reg mem_wb_req, output reg [31:0] mem_wb_addr, output reg [255:0] mem_wb_line,
    input wire mem_wb_done
);

    // --- Declarations ---
    reg [2:0] state;
    localparam IDLE=0, COMP=1, BREQ=2, WAIT=3, WB_EVICT=4;

    reg victim_way_r;  
    reg hit_way_r;     
    reg is_upgrade_r;  
    reg target_way;    // Declared as reg for use in always block
    
    reg [255:0] wline_buffer;
    
    wire [19:0] req_tag = cpu_addr[31:12];
    wire [6:0]  req_idx = cpu_addr[11:5];
    wire [1:0]  word_sel = cpu_addr[4:3];

    wire [19:0] tag0_r, tag1_r;
    wire [1:0]  state0_r, state1_r;
    wire [255:0] data0_r, data1_r;
    reg tag0_we, tag1_we, data0_we, data1_we;
    reg [1:0] next_state0, next_state1;
    reg fill_upd0, fill_upd1;
    wire lru_victim;

    wire hit0 = (state0_r != `STATE_I) && (tag0_r == req_tag);
    wire hit1 = (state1_r != `STATE_I) && (tag1_r == req_tag);
    wire hit  = hit0 || hit1;

    wire snoop_hit0 = (state0_r != `STATE_I) && (tag0_r == bus_addr_in[31:12]);
    wire snoop_hit1 = (state1_r != `STATE_I) && (tag1_r == bus_addr_in[31:12]);
    assign bus_data_out = snoop_hit0 ? data0_r : data1_r;

    // --- Instantiations ---
    lru lru_inst(.clk(clk), .rst(rst), .idx(req_idx), .hit0(hit0 || fill_upd0), .hit1(hit1 || fill_upd1), .victim(lru_victim));
    tag_array way0_t(.clk(clk), .we(tag0_we), .idx(req_idx), .wtag(req_tag), .wstate(next_state0), .rtag(tag0_r), .rstate(state0_r));
    tag_array way1_t(.clk(clk), .we(tag1_we), .idx(req_idx), .wtag(req_tag), .wstate(next_state1), .rtag(tag1_r), .rstate(state1_r));
    data_array way0_d(.clk(clk), .we(data0_we), .idx(req_idx), .wline(wline_buffer), .rline(data0_r));
    data_array way1_d(.clk(clk), .we(data1_we), .idx(req_idx), .wline(wline_buffer), .rline(data1_r));

    // --- FSM Logic ---
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; cpu_req_ready <= 1; bus_req_out <= `BUS_IDLE; 
            cpu_resp_valid <= 0; tag0_we <= 0; tag1_we <= 0;
            is_upgrade_r <= 0; target_way <= 0;
        end else begin
            tag0_we <= 0; tag1_we <= 0; data0_we <= 0; data1_we <= 0;
            fill_upd0 <= 0; fill_upd1 <= 0; cpu_resp_valid <= 0;
            snoop_hit_m <= (snoop_hit0 && state0_r == `STATE_M) || (snoop_hit1 && state1_r == `STATE_M);

            case (state)
                IDLE: if (cpu_req_valid) begin cpu_req_ready <= 0; state <= COMP; end
                
                COMP: begin
                    if (hit) begin
                        if (cpu_req_rw && ((hit0 && state0_r == `STATE_S) || (hit1 && state1_r == `STATE_S))) begin
                            hit_way_r <= hit1;    
                            is_upgrade_r <= 1;    
                            state <= BREQ;
                        end else begin
                            if (cpu_req_rw) begin 
                                wline_buffer = hit0 ? data0_r : data1_r;
                                wline_buffer[word_sel*64 +: 64] = cpu_wdata;
                                if (hit0) data0_we <= 1; else data1_we <= 1;
                            end else cpu_rdata <= hit0 ? data0_r[word_sel*64 +: 64] : data1_r[word_sel*64 +: 64];
                            cpu_resp_valid <= 1; cpu_req_ready <= 1; state <= IDLE;
                        end
                    end else begin
                        victim_way_r <= lru_victim; 
                        is_upgrade_r <= 0;
                        state <= ((lru_victim ? state1_r : state0_r) == `STATE_M) ? WB_EVICT : BREQ;
                    end
                end

                WB_EVICT: begin
                    mem_wb_req <= 1;
                    mem_wb_addr <= victim_way_r ? {tag1_r, req_idx, 5'b0} : {tag0_r, req_idx, 5'b0};
                    mem_wb_line <= victim_way_r ? data1_r : data0_r;
                    if (mem_wb_done) begin mem_wb_req <= 0; state <= BREQ; end
                end

                BREQ: begin
                    bus_req_out <= is_upgrade_r ? `BUS_UPGR : (cpu_req_rw ? `BUS_RDX : `BUS_RD);
                    bus_addr_out <= cpu_addr;
                    if (bus_grant) state <= WAIT;
                end

                WAIT: if (bus_data_vld) begin
                    target_way = is_upgrade_r ? hit_way_r : victim_way_r;
                    
                    wline_buffer = is_upgrade_r ? (target_way ? data1_r : data0_r) : bus_data_in;
                    
                    if (cpu_req_rw) wline_buffer[word_sel*64 +: 64] = cpu_wdata;

                    if (!target_way) begin 
                        tag0_we <= 1; next_state0 <= cpu_req_rw ? `STATE_M : `STATE_S; 
                        data0_we <= 1; fill_upd0 <= 1;
                    end else begin 
                        tag1_we <= 1; next_state1 <= cpu_req_rw ? `STATE_M : `STATE_S; 
                        data1_we <= 1; fill_upd1 <= 1;
                    end
                    bus_req_out <= `BUS_IDLE; cpu_resp_valid <= 1; cpu_req_ready <= 1; state <= IDLE;
                end
            endcase

            // Priority Snoop
            if (bus_cmd_in == `BUS_RDX || bus_cmd_in == `BUS_UPGR) begin
                if (snoop_hit0) begin tag0_we <= 1; next_state0 <= `STATE_I; end
                if (snoop_hit1) begin tag1_we <= 1; next_state1 <= `STATE_I; end
            end else if (bus_cmd_in == `BUS_RD && snoop_hit_m) begin
                if (snoop_hit0) begin tag0_we <= 1; next_state0 <= `STATE_S; end
                if (snoop_hit1) begin tag1_we <= 1; next_state1 <= `STATE_S; end
            end
        end
    end
endmodule
