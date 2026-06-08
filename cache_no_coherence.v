// cache_no_coherence.v
module cache_no_coherence #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter LINE_SIZE = 8,               // words per line (32 bytes)
    parameter CACHE_SIZE = 8192,           // total bytes (8 KB)
    parameter ASSOC = 2
) (
    input clk,
    input rst_n,

    input  cpu_req_valid,
    input  cpu_req_rw,
    input  [ADDR_WIDTH-1:0] cpu_addr,
    input  [DATA_WIDTH-1:0] cpu_wdata,
    output cpu_req_ready,
    output cpu_resp_valid,
    output [DATA_WIDTH-1:0] cpu_rdata,

    output mem_req_valid,
    output mem_req_rw,
    output [ADDR_WIDTH-1:0] mem_addr,
    output [DATA_WIDTH*LINE_SIZE-1:0] mem_wdata,
    input  mem_req_ready,
    input  mem_resp_valid,
    input  [DATA_WIDTH*LINE_SIZE-1:0] mem_rdata
);

    // Address breakdown
    localparam BYTES_PER_WORD = DATA_WIDTH/8;
    localparam BYTES_PER_LINE = LINE_SIZE * BYTES_PER_WORD;  // 32 bytes
    localparam OFFSET_BITS = $clog2(BYTES_PER_LINE);          // 5
    localparam INDEX_BITS = $clog2(CACHE_SIZE / (ASSOC * BYTES_PER_LINE)); // 7
    localparam TAG_BITS = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS; // 20
    localparam NUM_SETS = 1 << INDEX_BITS;                     // 128

    // Cache storage
    reg [TAG_BITS-1:0] tag [0:NUM_SETS-1][0:ASSOC-1];
    reg [DATA_WIDTH*LINE_SIZE-1:0] data [0:NUM_SETS-1][0:ASSOC-1];
    reg valid [0:NUM_SETS-1][0:ASSOC-1];
    reg dirty [0:NUM_SETS-1][0:ASSOC-1];

    // LRU tracking: per set, which way is most recently used (MRU)
    reg lru_mru [0:NUM_SETS-1];

    // FSM state and parameters
    reg [2:0] state;
    parameter [2:0] IDLE      = 3'd0,
                    READ_MISS = 3'd1,
                    WB_EVICT  = 3'd2,
                    WB_WAIT   = 3'd3;

    // Address breakdown wires
    wire [INDEX_BITS-1:0] index = cpu_addr[OFFSET_BITS +: INDEX_BITS];
    wire [TAG_BITS-1:0]   tag_in = cpu_addr[ADDR_WIDTH-1 -: TAG_BITS];
    wire [OFFSET_BITS-1:0] offset = cpu_addr[0 +: OFFSET_BITS];

    // Hit detection
    reg hit;
    reg [ASSOC-1:0] hit_way;
    integer way;
    always @(*) begin
        hit = 1'b0;
        hit_way = {ASSOC{1'b0}};
        for (way = 0; way < ASSOC; way = way + 1) begin
            if (valid[index][way] && tag[index][way] == tag_in) begin
                hit = 1'b1;
                hit_way = way;
            end
        end
    end

    // Registers for miss handling
    reg [DATA_WIDTH*LINE_SIZE-1:0] line_buffer;
    reg [ADDR_WIDTH-1:0] miss_addr;
    reg miss_rw;
    reg [$clog2(ASSOC)-1:0] victim_way_reg;

    // Output assignments
    assign cpu_req_ready = (state == IDLE);
    assign cpu_resp_valid = (state == IDLE && hit && !cpu_req_rw);
    assign cpu_rdata = (hit && !cpu_req_rw) ? data[index][hit_way][offset*DATA_WIDTH +: DATA_WIDTH] : {DATA_WIDTH{1'bx}};

    assign mem_req_valid = (state == READ_MISS || state == WB_EVICT);
    assign mem_req_rw = (state == WB_EVICT); // 1 for write-back
    assign mem_addr = (state == WB_EVICT) ? miss_addr : cpu_addr;
    assign mem_wdata = (state == WB_EVICT) ? line_buffer : {DATA_WIDTH*LINE_SIZE{1'bx}};

    // Loop variables
    integer s, w;
    integer victim_way;

    // Function to find victim way (LRU or first invalid)
    function integer find_victim;
        input [INDEX_BITS-1:0] set;
        integer w;
        reg found;
        begin
            found = 1'b0;
            find_victim = 0;
            for (w = 0; w < ASSOC; w = w + 1) begin
                if (!valid[set][w]) begin
                    find_victim = w;
                    found = 1'b1;
                    w = ASSOC; // break loop
                end
            end
            if (!found) begin
                // all ways valid → use LRU (the way that is NOT the MRU)
                find_victim = (1 - lru_mru[set]);
            end
        end
    endfunction

    // Task to update LRU
    task update_lru;
        input [INDEX_BITS-1:0] set;
        input integer used_way;
        begin
            lru_mru[set] = used_way;
        end
    endtask

    // Main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            for (s = 0; s < NUM_SETS; s = s + 1) begin
                for (w = 0; w < ASSOC; w = w + 1) begin
                    valid[s][w] <= 1'b0;
                    dirty[s][w] <= 1'b0;
                end
                lru_mru[s] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (cpu_req_valid) begin
                        if (hit) begin
                            update_lru(index, hit_way);
                            if (cpu_req_rw) begin
                                data[index][hit_way][offset*DATA_WIDTH +: DATA_WIDTH] <= cpu_wdata;
                                dirty[index][hit_way] <= 1'b1;
                            end
                        end else begin
                            miss_addr <= cpu_addr;
                            miss_rw <= cpu_req_rw;
                            victim_way = find_victim(index);
                            victim_way_reg <= victim_way;
                            if (valid[index][victim_way] && dirty[index][victim_way]) begin
                                // Victim dirty: need write-back first
                                state <= WB_EVICT;
                                line_buffer <= data[index][victim_way];
                            end else begin
                                // Victim clean or invalid: go directly to read miss
                                state <= READ_MISS;
                            end
                        end
                    end
                end

                WB_EVICT: begin
                    if (mem_req_ready) begin
                        state <= WB_WAIT;
                    end
                end

                WB_WAIT: begin
                    if (mem_resp_valid) begin
                        state <= READ_MISS;
                    end
                end

                READ_MISS: begin
                    if (mem_resp_valid) begin
                        // Fill cache line
                        data[index][victim_way_reg] <= mem_rdata;
                        tag[index][victim_way_reg] <= tag_in;
                        valid[index][victim_way_reg] <= 1'b1;
                        dirty[index][victim_way_reg] <= 1'b0;
                        update_lru(index, victim_way_reg);
                        // If original request was write, perform it now
                        if (miss_rw) begin
                            data[index][victim_way_reg][offset*DATA_WIDTH +: DATA_WIDTH] <= cpu_wdata;
                            dirty[index][victim_way_reg] <= 1'b1;
                        end
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
