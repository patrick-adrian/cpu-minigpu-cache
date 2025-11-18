`timescale 1ns/1ps
module d_cache #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter NUM_SETS = 64,
  parameter ASSOC = 4,
  parameter LINE_WORDS = 1
)(
  input  logic                    clk,
  input  logic                    rst_n,
  // CPU side (MEM)
  input  logic [ADDR_WIDTH-1:0]   cpu_addr,
  input  logic                    cpu_rd,
  input  logic                    cpu_wr,
  input  logic [DATA_WIDTH-1:0]   cpu_wdata,
  output logic [DATA_WIDTH-1:0]   cpu_rdata,
  output logic                    cpu_ready,
  // Memory side (to L2 or memory)
  output logic [ADDR_WIDTH-1:0]   mem_addr,
  output logic                    mem_rd,
  output logic                    mem_wr,
  output logic [DATA_WIDTH-1:0]   mem_wdata,
  input  logic [DATA_WIDTH-1:0]   mem_rdata,
  input  logic                    mem_ready
);
  localparam SET_BITS = $clog2(NUM_SETS);
  localparam OFFSET_BITS = $clog2(LINE_WORDS);
  localparam TAG_BITS = ADDR_WIDTH - SET_BITS - OFFSET_BITS;

  wire [SET_BITS-1:0] set = cpu_addr[OFFSET_BITS +: SET_BITS];
  wire [OFFSET_BITS-1:0] off = cpu_addr[0 +: OFFSET_BITS];
  wire [TAG_BITS-1:0] tag = cpu_addr[ADDR_WIDTH-1 -: TAG_BITS];

  typedef struct packed {
    logic valid;
    logic dirty;
    logic [TAG_BITS-1:0] tag;
    logic [DATA_WIDTH-1:0] data;
  } line_t;

  line_t cache_mem [0:NUM_SETS-1][0:ASSOC-1];
  logic [$clog2(ASSOC)-1:0] lru_age [0:NUM_SETS-1][0:ASSOC-1];

  // hit detection
  logic hit;
  logic [$clog2(ASSOC)-1:0] hit_way;
  integer i;
  always_comb begin
    hit = 0;
    hit_way = '0;
    for (i=0;i<ASSOC;i=i+1) begin
      if (cache_mem[set][i].valid && cache_mem[set][i].tag == tag) begin
        hit = 1;
        hit_way = i;
      end
    end
  end

  // miss/writeback state
  logic pending_miss;
  logic pending_writeback;
  logic [$clog2(ASSOC)-1:0] repl_way;
  logic [$clog2(ASSOC)-1:0] wb_way;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cpu_ready <= 0;
      cpu_rdata <= '0;
      mem_rd <= 0;
      mem_wr <= 0;
      pending_miss <= 0;
      pending_writeback <= 0;
      for (int s=0; s<NUM_SETS; s=s+1) begin
        for (int w=0; w<ASSOC; w=w+1) begin
          cache_mem[s][w].valid <= 1'b0;
          cache_mem[s][w].dirty <= 1'b0;
          cache_mem[s][w].tag <= '0;
          cache_mem[s][w].data <= '0;
          lru_age[s][w] <= w;
        end
      end
    end else begin
      cpu_ready <= 0;
      mem_rd <= 0;
      mem_wr <= 0;

      if (!pending_miss && !pending_writeback) begin
        if (cpu_rd || cpu_wr) begin
          if (hit) begin
            // Hit
            cpu_ready <= 1;
            if (cpu_rd) cpu_rdata <= cache_mem[set][hit_way].data;
            if (cpu_wr) begin
              cache_mem[set][hit_way].data <= cpu_wdata;
              cache_mem[set][hit_way].dirty <= 1;
            end
            // LRU update
            for (int w=0; w<ASSOC; w=w+1) begin
              if (w==hit_way) lru_age[set][w] <= 0;
              else if (lru_age[set][w] < lru_age[set][hit_way]) lru_age[set][w] <= lru_age[set][w] + 1;
            end
          end else begin
            // Miss -> choose victim
            repl_way = 0;
            for (int w=0; w<ASSOC; w=w+1) begin
              if (lru_age[set][w] > lru_age[set][repl_way]) repl_way = w;
            end
            if (cache_mem[set][repl_way].valid && cache_mem[set][repl_way].dirty) begin
              // writeback victim first
              pending_writeback <= 1;
              wb_way <= repl_way;
              mem_addr <= {cache_mem[set][repl_way].tag, set, {OFFSET_BITS{1'b0}}};
              mem_wdata <= cache_mem[set][repl_way].data;
              mem_wr <= 1;
            end else begin
              // fetch new line
              pending_miss <= 1;
              mem_addr <= {cpu_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
              mem_rd <= 1;
            end
          end
        end
      end else if (pending_writeback) begin
        // wait for writeback completion, then issue fetch
        if (mem_ready) begin
          pending_writeback <= 0;
          pending_miss <= 1;
          mem_addr <= {cpu_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
          mem_rd <= 1;
        end
      end else if (pending_miss) begin
        if (mem_ready) begin
          // fill victim way
          cache_mem[set][repl_way].data <= mem_rdata;
          cache_mem[set][repl_way].tag <= tag;
          cache_mem[set][repl_way].valid <= 1;
          cache_mem[set][repl_way].dirty <= 0;
          // update ages
          for (int w=0; w<ASSOC; w=w+1) begin
            if (w==repl_way) lru_age[set][w] <= 0;
            else lru_age[set][w] <= lru_age[set][w] + 1;
          end
          // service original request
          cpu_ready <= 1;
          if (cpu_rd) cpu_rdata <= mem_rdata;
          else if (cpu_wr) begin
            cache_mem[set][repl_way].data <= cpu_wdata;
            cache_mem[set][repl_way].dirty <= 1;
          end
          pending_miss <= 0;
        end
      end
    end
  end

endmodule
