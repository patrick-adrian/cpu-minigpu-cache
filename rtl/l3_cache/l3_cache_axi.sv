`timescale 1ns/1ps
// l3_cache_axi.sv - L3 cache with AXI4-lite master downstream (single-beat)
// Simplified: supports single-beat AR/R and AW/W/B channels (no bursts), write-back & write-allocate.
// Connects upstream as simplified AXI-like slave (from L2) and downstream as AXI master to RAM.
module l3_cache_axi #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter NUM_SETS = 1024,
  parameter ASSOC = 8,
  parameter LINE_WORDS = 1
)(
  input  logic                   clk,
  input  logic                   rst_n,
  // -------------------
  // Upstream simplified slave (from L2)
  input  logic [ADDR_WIDTH-1:0]  s_araddr,
  input  logic                   s_arvalid,
  output logic                   s_arready,
  output logic [DATA_WIDTH-1:0]  s_rdata,
  output logic                   s_rvalid,
  input  logic                   s_rready,
  input  logic [ADDR_WIDTH-1:0]  s_awaddr,
  input  logic                   s_awvalid,
  output logic                   s_awready,
  input  logic [DATA_WIDTH-1:0]  s_wdata,
  input  logic                   s_wvalid,
  output logic                   s_wready,
  output logic                   s_bvalid,
  input  logic                   s_bready,
  // -------------------
  // Downstream AXI4-lite Master (to DRAM/RAM)
  // Read addr channel
  output logic [ADDR_WIDTH-1:0]  m_araddr,
  output logic                   m_arvalid,
  input  logic                   m_arready,
  // Read data channel
  input  logic [DATA_WIDTH-1:0]  m_rdata,
  input  logic                   m_rvalid,
  output logic                   m_rready,
  // Write addr channel
  output logic [ADDR_WIDTH-1:0]  m_awaddr,
  output logic                   m_awvalid,
  input  logic                   m_awready,
  // Write data channel
  output logic [DATA_WIDTH-1:0]  m_wdata,
  output logic [DATA_WIDTH/8-1:0] m_wstrb,
  output logic                   m_wvalid,
  input  logic                   m_wready,
  // Write resp
  input  logic                   m_bvalid,
  output logic                   m_bready
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

  // storage
  line_t cache_mem [0:NUM_SETS-1][0:ASSOC-1];
  logic [$clog2(ASSOC)-1:0] lru_age [0:NUM_SETS-1][0:ASSOC-1];

  // decode
  wire [SET_BITS-1:0] set_ar = s_araddr[OFFSET_BITS +: SET_BITS];
  wire [OFFSET_BITS-1:0] off_ar = s_araddr[0 +: OFFSET_BITS];
  wire [TAG_BITS-1:0] tag_ar = s_araddr[ADDR_WIDTH-1 -: TAG_BITS];

  wire [SET_BITS-1:0] set_aw = s_awaddr[OFFSET_BITS +: SET_BITS];
  wire [OFFSET_BITS-1:0] off_aw = s_awaddr[0 +: OFFSET_BITS];
  wire [TAG_BITS-1:0] tag_aw = s_awaddr[ADDR_WIDTH-1 -: TAG_BITS];

  // hits
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

  // FSM states
  typedef enum logic [2:0] {IDLE, RESP_READ, ALLOC_READ, WB_WRITEBACK, RESP_WRITE, AXI_WAIT_R, AXI_WAIT_B} state_t;
  state_t state;

  logic [$clog2(ASSOC)-1:0] repl_way;
  logic [$clog2(ASSOC)-1:0] chosen_way;

  // saved reqs
  logic [ADDR_WIDTH-1:0] saved_araddr;
  logic [ADDR_WIDTH-1:0] saved_awaddr;
  logic [DATA_WIDTH-1:0] saved_wdata;

  // default outputs
  assign s_arready = (state == IDLE);
  assign s_awready = (state == IDLE);
  assign s_wready  = (state == IDLE);
  assign s_rvalid  = (state == RESP_READ);
  assign s_bvalid  = (state == RESP_WRITE);

  // default AXI master outputs idle
  assign m_araddr = (state == ALLOC_READ) ? saved_araddr : '0;
  assign m_arvalid = (state == ALLOC_READ);
  assign m_rready = (state == AXI_WAIT_R);

  assign m_awaddr = (state == WB_WRITEBACK) ? {cache_mem[set_ar][chosen_way].tag, set_ar, {OFFSET_BITS{1'b0}}} : '0;
  assign m_awvalid = (state == WB_WRITEBACK);
  assign m_wdata = (state == WB_WRITEBACK) ? cache_mem[set_ar][chosen_way].data : '0;
  assign m_wstrb = {(DATA_WIDTH/8){1'b1}};
  assign m_wvalid = (state == WB_WRITEBACK);
  assign m_bready = (state == AXI_WAIT_B);

  // AXI handshake registers to avoid combinational loops
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      s_rdata <= '0;
      s_bvalid <= 1'b0;
      // init cache
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
      // default outputs
      s_bvalid <= 1'b0;
      s_rdata <= '0;
      // FSM
      case (state)
        IDLE: begin
          if (s_arvalid) begin
            saved_araddr <= s_araddr;
            // if hit return
            if (ar_hit) begin
              s_rdata <= cache_mem[set_ar][ar_hit_way].data;
              // update LRU
              for (int w=0; w<ASSOC; w=w+1) begin
                if (w==ar_hit_way) lru_age[set_ar][w] <= 0;
                else if (lru_age[set_ar][w] < lru_age[set_ar][ar_hit_way]) lru_age[set_ar][w] <= lru_age[set_ar][w] + 1;
              end
              state <= RESP_READ;
            end else begin
              // miss: pick repl_way
              repl_way = '0;
              for (int w=0; w<ASSOC; w=w+1) begin
                if (!cache_mem[set_ar][w].valid) begin repl_way = w; break; end
              end
              chosen_way <= repl_way;
              // if dirty victim -> writeback
              if (cache_mem[set_ar][chosen_way].valid && cache_mem[set_ar][chosen_way].dirty) begin
                state <= WB_WRITEBACK;
              end else begin
                // issue AXI read
                saved_araddr <= {s_araddr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
                state <= ALLOC_READ;
              end
            end
          end else if (s_awvalid && s_wvalid) begin
            saved_awaddr <= s_awaddr;
            saved_wdata <= s_wdata;
            if (aw_hit) begin
              cache_mem[set_aw][aw_hit_way].data <= s_wdata;
              cache_mem[set_aw][aw_hit_way].dirty <= 1;
              // update LRU
              for (int w=0; w<ASSOC; w=w+1) begin
                if (w==aw_hit_way) lru_age[set_aw][w] <= 0;
                else if (lru_age[set_aw][w] < lru_age[set_aw][aw_hit_way]) lru_age[set_aw][w] <= lru_age[set_aw][w] + 1;
              end
              state <= RESP_WRITE;
            end else begin
              // write-allocate: pick repl way
              repl_way = '0;
              for (int w=0; w<ASSOC; w=w+1) begin
                if (!cache_mem[set_aw][w].valid) begin repl_way = w; break; end
              end
              chosen_way <= repl_way;
              if (cache_mem[set_aw][chosen_way].valid && cache_mem[set_aw][chosen_way].dirty) begin
                state <= WB_WRITEBACK;
              end else begin
                saved_araddr <= {s_awaddr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
                state <= ALLOC_READ;
              end
            end
          end
        end

        WB_WRITEBACK: begin
          // initiate AXI AW/W
          if (m_awready && m_wready) begin
            state <= AXI_WAIT_B;
          end
        end

        AXI_WAIT_B: begin
          if (m_bvalid) begin
            // writeback acknowledged
            cache_mem[set_ar][chosen_way].dirty <= 0;
            // proceed to issue read for allocate
            state <= ALLOC_READ;
            saved_araddr <= {s_araddr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
          end
        end

        ALLOC_READ: begin
          // wait for m_rvalid
          if (m_rvalid) begin
            // fill cache line (single-word)
            cache_mem[set_ar][chosen_way].data <= m_rdata;
            cache_mem[set_ar][chosen_way].tag <= tag_ar;
            cache_mem[set_ar][chosen_way].valid <= 1;
            cache_mem[set_ar][chosen_way].dirty <= 0;
            s_rdata <= m_rdata;
            state <= RESP_READ;
          end
        end

        RESP_READ: begin
          if (s_rready) begin
            s_rdata <= '0;
            state <= IDLE;
          end
        end

        RESP_WRITE: begin
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
