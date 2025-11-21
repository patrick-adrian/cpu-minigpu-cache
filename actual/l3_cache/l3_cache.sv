`timescale 1ns/1ps
// l3_cache.sv - Simple unified L3 cache
// - AXI-lite style slave upstream (from L2): AR/ R and AW/W/B channels (single-beat simple)
// - Simple downstream memory interface (mem_addr/mem_rd/mem_wr/mem_wdata/mem_rdata/mem_ready)
// - Single-word lines for simplicity
// - Write-back, write-allocate, pseudo-LRU replacement
module l3_cache #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter NUM_SETS = 1024,
  parameter ASSOC = 8,
  parameter LINE_WORDS = 1
)(
  input  logic                   clk,
  input  logic                   rst_n,
  // -------------------
  // Upstream AXI Slave (from L2) - simplified single-beat
  // Read address channel
  input  logic [ADDR_WIDTH-1:0]  s_araddr,
  input  logic                   s_arvalid,
  output logic                   s_arready,
  // Read data channel
  output logic [DATA_WIDTH-1:0]  s_rdata,
  output logic                   s_rvalid,
  input  logic                   s_rready,
  // Write address channel
  input  logic [ADDR_WIDTH-1:0]  s_awaddr,
  input  logic                   s_awvalid,
  output logic                   s_awready,
  // Write data channel
  input  logic [DATA_WIDTH-1:0]  s_wdata,
  input  logic                   s_wvalid,
  output logic                   s_wready,
  // Write response channel
  output logic                   s_bvalid,
  input  logic                   s_bready,
  // -------------------
  // Downstream simple memory interface (toward DRAM or RAM model)
  output logic [ADDR_WIDTH-1:0]  mem_addr,
  output logic                   mem_rd,
  output logic                   mem_wr,
  output logic [DATA_WIDTH-1:0]  mem_wdata,
  input  logic [DATA_WIDTH-1:0]   mem_rdata,
  input  logic                    mem_ready
);

  // parameters
  localparam SET_BITS = $clog2(NUM_SETS);
  localparam OFFSET_BITS = $clog2(LINE_WORDS);
  localparam TAG_BITS = ADDR_WIDTH - SET_BITS - OFFSET_BITS;

  typedef struct packed {
    logic valid;
    logic dirty;
    logic [TAG_BITS-1:0] tag;
    logic [DATA_WIDTH-1:0] data;
  } line_t;

  // cache storage
  line_t cache_mem [0:NUM_SETS-1][0:ASSOC-1];
  logic [$clog2(ASSOC)-1:0] lru_age [0:NUM_SETS-1][0:ASSOC-1];

  // internal request decode
  wire [SET_BITS-1:0] set_ar = s_araddr[OFFSET_BITS +: SET_BITS];
  wire [OFFSET_BITS-1:0] off_ar = s_araddr[0 +: OFFSET_BITS];
  wire [TAG_BITS-1:0] tag_ar = s_araddr[ADDR_WIDTH-1 -: TAG_BITS];

  wire [SET_BITS-1:0] set_aw = s_awaddr[OFFSET_BITS +: SET_BITS];
  wire [OFFSET_BITS-1:0] off_aw = s_awaddr[0 +: OFFSET_BITS];
  wire [TAG_BITS-1:0] tag_aw = s_awaddr[ADDR_WIDTH-1 -: TAG_BITS];

  // hit detection for read and write (we search on request)
  logic ar_hit;
  logic [$clog2(ASSOC)-1:0] ar_hit_way;
  logic aw_hit;
  logic [$clog2(ASSOC)-1:0] aw_hit_way;

  integer i;
  always_comb begin
    ar_hit = 0; ar_hit_way = '0;
    aw_hit = 0; aw_hit_way = '0;
    for (i=0; i<ASSOC; i=i+1) begin
      if (cache_mem[set_ar][i].valid && cache_mem[set_ar][i].tag == tag_ar) begin
        ar_hit = 1; ar_hit_way = i;
      end
      if (cache_mem[set_aw][i].valid && cache_mem[set_aw][i].tag == tag_aw) begin
        aw_hit = 1; aw_hit_way = i;
      end
    end
  end

  // states for simple FSM
  typedef enum logic [2:0] {IDLE, RESP_READ, ALLOC_READ, WB_WRITEBACK, RESP_WRITE} state_t;
  state_t state, next_state;

  // replacer
  logic [$clog2(ASSOC)-1:0] repl_way;
  logic [$clog2(ASSOC)-1:0] chosen_way;

  // pipeline registers for responses
  logic [ADDR_WIDTH-1:0] saved_araddr;
  logic [ADDR_WIDTH-1:0] saved_awaddr;
  logic [DATA_WIDTH-1:0] saved_wdata;

  // outputs default
  assign s_arready = (state == IDLE);
  assign s_awready = (state == IDLE);
  assign s_wready  = (state == IDLE);
  assign s_rvalid  = (state == RESP_READ);
  assign s_bvalid  = (state == RESP_WRITE);

  // default downstream signals (driven in FSM)
  logic mem_rd_r, mem_wr_r;
  logic [ADDR_WIDTH-1:0] mem_addr_r;
  logic [DATA_WIDTH-1:0] mem_wdata_r;
  assign mem_rd = mem_rd_r;
  assign mem_wr = mem_wr_r;
  assign mem_addr = mem_addr_r;
  assign mem_wdata = mem_wdata_r;

  // on reset initialize
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      s_rdata <= '0;
      s_bvalid <= 1'b0;
      mem_rd_r <= 0;
      mem_wr_r <= 0;
      mem_addr_r <= '0;
      mem_wdata_r <= '0;
      // init cache entries and ages
      for (int s=0; s<NUM_SETS; s=s+1) begin
        for (int w=0; w<ASSOC; w=w+1) begin
          cache_mem[s][w].valid <= 1'b0;
          cache_mem[s][w].dirty <= 1'b0;
          cache_mem[s][w].tag   <= '0;
          cache_mem[s][w].data  <= '0;
          lru_age[s][w] <= w;
        end
      end
    end else begin
      // default outputs each cycle unless FSM drives them
      s_bvalid <= 1'b0;
      s_rdata <= '0;
      mem_rd_r <= 0;
      mem_wr_r <= 0;
      mem_addr_r <= '0;
      mem_wdata_r <= '0;

      case (state)
        IDLE: begin
          if (s_arvalid) begin
            // handle read request from upstream L2
            saved_araddr <= s_araddr;
            if (ar_hit) begin
              // L3 hit: respond immediately
              s_rdata <= cache_mem[set_ar][ar_hit_way].data;
              // update LRU: hit way -> age 0; increment others
              for (int w=0; w<ASSOC; w=w+1) begin
                if (w == ar_hit_way) lru_age[set_ar][w] <= 0;
                else if (lru_age[set_ar][w] < lru_age[set_ar][ar_hit_way]) lru_age[set_ar][w] <= lru_age[set_ar][w] + 1;
              end
              state <= RESP_READ;
            end else begin
              // miss: allocate way and fetch from mem
              // choose repl_way: prefer invalid
              repl_way = '0;
              for (int w=0; w<ASSOC; w=w+1) begin
                if (!cache_mem[set_ar][w].valid) begin
                  repl_way = w; break;
                end
                if (w == 0) repl_way = 0; // default fallback
              end
              chosen_way <= repl_way;
              // if dirty victim need writeback first
              if (cache_mem[set_ar][chosen_way].valid && cache_mem[set_ar][chosen_way].dirty) begin
                // issue writeback to downstream memory
                mem_addr_r <= {cache_mem[set_ar][chosen_way].tag, set_ar, {OFFSET_BITS{1'b0}}};
                mem_wdata_r <= cache_mem[set_ar][chosen_way].data;
                mem_wr_r <= 1;
                state <= WB_WRITEBACK;
              end else begin
                // issue read to mem
                mem_addr_r <= {s_araddr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
                mem_rd_r <= 1;
                state <= ALLOC_READ;
              end
            end
          end else if (s_awvalid && s_wvalid) begin
            // write request (AW + W arrived concurrently)
            saved_awaddr <= s_awaddr;
            saved_wdata <= s_wdata;
            if (aw_hit) begin
              // write hit: update data and mark dirty
              cache_mem[set_aw][aw_hit_way].data <= s_wdata;
              cache_mem[set_aw][aw_hit_way].dirty <= 1;
              // update LRU ages
              for (int w=0; w<ASSOC; w=w+1) begin
                if (w==aw_hit_way) lru_age[set_aw][w] <= 0;
                else if (lru_age[set_aw][w] < lru_age[set_aw][aw_hit_way]) lru_age[set_aw][w] <= lru_age[set_aw][w] + 1;
              end
              state <= RESP_WRITE;
            end else begin
              // miss on write -> write-allocate: fetch line then write
              repl_way = '0;
              for (int w=0; w<ASSOC; w=w+1) begin
                if (!cache_mem[set_aw][w].valid) begin
                  repl_way = w; break;
                end
              end
              chosen_way <= repl_way;
              if (cache_mem[set_aw][chosen_way].valid && cache_mem[set_aw][chosen_way].dirty) begin
                mem_addr_r <= {cache_mem[set_aw][chosen_way].tag, set_aw, {OFFSET_BITS{1'b0}}};
                mem_wdata_r <= cache_mem[set_aw][chosen_way].data;
                mem_wr_r <= 1;
                state <= WB_WRITEBACK;
              end else begin
                mem_addr_r <= {s_awaddr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
                mem_rd_r <= 1;
                state <= ALLOC_READ;
              end
            end
          end
        end

        WB_WRITEBACK: begin
          // wait for mem_ready on writeback
          if (mem_ready) begin
            // clear writeback signals and start pending read
            mem_wr_r <= 0;
            mem_addr_r <= {saved_araddr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
            mem_rd_r <= 1;
            state <= ALLOC_READ;
          end
        end

        ALLOC_READ: begin
          // wait for mem_ready indicating data available
          if (mem_ready) begin
            // fill chosen_way with mem_rdata (single-word)
            cache_mem[set_ar][chosen_way].data <= mem_rdata;
            cache_mem[set_ar][chosen_way].tag  <= tag_ar;
            cache_mem[set_ar][chosen_way].valid <= 1;
            cache_mem[set_ar][chosen_way].dirty <= 0;
            // respond to original requester
            s_rdata <= mem_rdata;
            state <= RESP_READ;
            mem_rd_r <= 0;
          end
        end

        RESP_READ: begin
          // wait for upstream to accept read data
          if (s_rready) begin
            s_rdata <= '0;
            state <= IDLE;
          end
        end

        RESP_WRITE: begin
          // provide write response
          s_bvalid <= 1;
          if (s_bready) begin
            s_bvalid <= 0;
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
