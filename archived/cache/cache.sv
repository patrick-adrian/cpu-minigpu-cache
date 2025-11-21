`timescale 1ns/1ps
module cache #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter LINE_SIZE  = 4,      // words per line
    parameter NUM_SETS   = 16,     // number of cache sets
    parameter ASSOC      = 2,      // n-way set associative
    parameter REPL_LRU   = 1,      // 1 = LRU, 0 = FIFO
    parameter WRITE_BACK = 1       // 1 = write-back, 0 = write-through
)(
    input  logic clk,
    input  logic rst_n,

    // CPU interface
    input  logic [ADDR_WIDTH-1:0] cpu_addr,
    input  logic                  cpu_rd,
    input  logic                  cpu_wr,
    input  logic [DATA_WIDTH-1:0] cpu_wdata,
    output logic [DATA_WIDTH-1:0] cpu_rdata,
    output logic                  cpu_ready,

    // Memory interface
    output logic [ADDR_WIDTH-1:0] mem_addr,
    output logic                  mem_rd,
    output logic                  mem_wr,
    output logic [DATA_WIDTH-1:0] mem_wdata,
    input  logic [DATA_WIDTH-1:0] mem_rdata,
    input  logic                  mem_ready
);

    // -------------------------
    // Address breakdown
    localparam SET_BITS    = $clog2(NUM_SETS);
    localparam OFFSET_BITS = $clog2(LINE_SIZE);
    localparam TAG_BITS    = ADDR_WIDTH - SET_BITS - OFFSET_BITS;

    wire [SET_BITS-1:0]    set_index = cpu_addr[OFFSET_BITS +: SET_BITS];
    wire [OFFSET_BITS-1:0] word_offset = cpu_addr[0 +: OFFSET_BITS];
    wire [TAG_BITS-1:0]    tag = cpu_addr[ADDR_WIDTH-1 -: TAG_BITS];

    // -------------------------
    // Cache line structure
    typedef struct packed {
        logic valid;
        logic dirty;
        logic [TAG_BITS-1:0] tag;
        logic [DATA_WIDTH-1:0] data[LINE_SIZE-1:0];
    } cache_line_t;

    cache_line_t cache_mem [0:NUM_SETS-1][0:ASSOC-1];

    // Replacement metadata
    logic [$clog2(ASSOC)-1:0] repl_ptr [0:NUM_SETS-1];   // points to LRU/FIFO line

    // -------------------------
    // Hit detection
    logic hit;
    logic [$clog2(ASSOC)-1:0] hit_way;

    always_comb begin
        hit = 0;
        hit_way = 0;
        for (int i = 0; i < ASSOC; i++) begin
            if (cache_mem[set_index][i].valid && cache_mem[set_index][i].tag == tag) begin
                hit = 1;
                hit_way = i;
            end
        end
    end

    // -------------------------
    // CPU ready/data
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_ready <= 0;
            cpu_rdata <= 0;
        end else begin
            cpu_ready <= 0;
            if (cpu_rd || cpu_wr) begin
                if (hit) begin
                    // Cache hit
                    cpu_ready <= 1;
                    if (cpu_rd)
                        cpu_rdata <= cache_mem[set_index][hit_way].data[word_offset];
                    if (cpu_wr) begin
                        cache_mem[set_index][hit_way].data[word_offset] <= cpu_wdata;
                        if (WRITE_BACK)
                            cache_mem[set_index][hit_way].dirty <= 1;
                        else begin
                            mem_addr <= cpu_addr;
                            mem_wdata <= cpu_wdata;
                            mem_wr <= 1;
                        end
                    end
                end else begin
                    // Cache miss
                    cpu_ready <= 0;
                    mem_addr <= cpu_addr;
                    mem_rd <= cpu_rd;
                    mem_wr <= 0;
                end
            end
        end
    end

    // -------------------------
    // Handle memory response and replacement
    always_ff @(posedge clk) begin
        if (mem_ready && mem_rd) begin
            // Select replacement way
            logic [$clog2(ASSOC)-1:0] way;
            way = repl_ptr[set_index];

            // Write back if dirty
            if (WRITE_BACK && cache_mem[set_index][way].valid && cache_mem[set_index][way].dirty) begin
                mem_addr <= {cache_mem[set_index][way].tag, set_index, {OFFSET_BITS{1'b0}}};
                mem_wdata <= cache_mem[set_index][way].data[word_offset];
                mem_wr <= 1;
            end

            // Fill cache line
            cache_mem[set_index][way].data[word_offset] <= mem_rdata;
            cache_mem[set_index][way].valid <= 1;
            cache_mem[set_index][way].tag <= tag;
            cache_mem[set_index][way].dirty <= 0;
            cpu_rdata <= mem_rdata;
            cpu_ready <= 1;

            // Update replacement pointer (LRU/FIFO)
            if (REPL_LRU)
                repl_ptr[set_index] <= (repl_ptr[set_index] + 1) % ASSOC;
            else
                repl_ptr[set_index] <= (repl_ptr[set_index] + 1) % ASSOC;

            mem_rd <= 0;
            mem_wr <= 0;
        end
    end

endmodule
