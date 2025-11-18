`timescale 1ns/1ps
// l2_cache_axi.sv - Unified L2 cache with AXI4-lite downstream master
// Simplified single-beat AXI behavior (no bursts), write-back & write-allocate.
// Upstream: simple request/response interface from L1 caches (read/write).
module l2_cache_axi #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter NUM_SETS = 1024,
  parameter ASSOC = 8,
  parameter LINE_WORDS = 1
)(
  input  logic                   clk,
  input  logic                   rst_n,
  // -------------------
  // Upstream simple slave (from L1 caches / arbiter)
  // One upstream request port: valid + addr + we + wdata
  input  logic                   s_req_valid,
  input  logic [ADDR_WIDTH-1:0]  s_req_addr,
  input  logic                   s_req_we,       // 1 = write, 0 = read
  input  logic [DATA_WIDTH-1:0]  s_req_wdata,
  output logic [DATA_WIDTH-1:0]  s_rsp_rdata,
  output logic                   s_rsp_valid,
  input  logic                   s_rsp_ready,
  // -------------------
  // Downstream AXI4-lite Master (to L3)
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
  wire [SET_BITS-1:0] set_req = s_req_addr[OFFSET_BITS +: SET_BITS];
  wire [OFFSET_BITS-1:0] off_req = s_req_addr[0 +: OFFSET_BITS];
  wire [TAG_BITS-1:0] tag_req = s_req_addr[ADDR_WIDTH-1 -: TAG_BITS];

  // hit detection
  logic req_hit;
  logic [$clog2(ASSOC)-1:0] req_hit_way;
  integer i;
  always_comb begin
    req_hit = 0; req_hit_way = '0;
    for (i=0; i<ASSOC; i=i+1) begin
      if (cache_mem[set_req][i].valid && cache_mem[set_req][i].tag == tag_req) begin
        req_hit = 1;
        req_hit_way = i;
      end
    end
  end

  // FSM states
  typedef enum logic [2:0] {
    IDLE,
    RESP_READ,
    ALLOC_READ,
    WB_WRITEBACK,
    RESP_WRITE,
    AXI_WAIT_B
  } state_t;
  state_t state;

  logic [$clog2(ASSOC)-1:0] repl_way;
  logic [$clog2(ASSOC)-1:0] chosen_way;

  // saved request info
  logic [ADDR_WIDTH-1:0] saved_req_addr;
  logic saved_req_we;
  logic [DATA_WIDTH-1:0] saved_req_wdata;

  // outputs default
  assign s_rsp_valid = (state == RESP_READ) || (state == RESP_WRITE);
  assign s_rsp_rdata = (state == RESP_READ) ? cache_mem[set_req][req_hit_way].data : '0;

  // AXI master outputs default (driven combinationally depending on state)
  assign m_araddr  = (state == ALLOC_READ) ? saved_req_addr : '0;
  assign m_arvalid = (state == ALLOC_READ);
  assign m_rready  = (state == ALLOC_READ);

  assign m_awaddr  = (state == WB_WRITEBACK) ? {cache_mem[set_req][chosen_way].tag, set_req, {OFFSET_BITS{1'b0}}} : '0;
  assign m_awvalid = (state == WB_WRITEBACK);
  assign m_wdata   = (state == WB_WRITEBACK) ? cache_mem[set_req][chosen_way].data : '0;
  assign m_wstrb   = {(DATA_WIDTH/8){1'b1}};
  assign m_wvalid  = (state == WB_WRITEBACK);
  assign m_bready  = (state == AXI_WAIT_B);

  // reset/init
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      s_rsp_rdata <= '0;
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
      // clear AXI-ready handshake outputs (they are inputs on master)
      // nothing else to init
    end else begin
      // default clear response signals (they are driven via state)
      s_rsp_rdata <= '0;

      case (state)
        IDLE: begin
          if (s_req_valid) begin
            // capture request
            saved_req_addr  <= s_req_addr;
            saved_req_we    <= s_req_we;
            saved_req_wdata <= s_req_wdata;
            // If hit, service immediately
            if (req_hit) begin
              if (!s_req_we) begin
                // Read hit: return data (use the req_hit_way)
                s_rsp_rdata <= cache_mem[set_req][req_hit_way].data;
                // update LRU: make hit_way MRU (age=0), increment others that were younger
                for (int w=0; w<ASSOC; w=w+1) begin
                  if (w == req_hit_way) lru_age[set_req][w] <= 0;
                  else if (lru_age[set_req][w] < lru_age[set_req][req_hit_way]) lru_age[set_req][w] <= lru_age[set_req][w] + 1;
                end
                state <= RESP_READ;
              end else begin
                // Write hit: update data and mark dirty
                cache_mem[set_req][req_hit_way].data <= s_req_wdata;
                cache_mem[set_req][req_hit_way].dirty <= 1;
                // update LRU
                for (int w=0; w<ASSOC; w=w+1) begin
                  if (w == req_hit_way) lru_age[set_req][w] <= 0;
                  else if (lru_age[set_req][w] < lru_age[set_req][req_hit_way]) lru_age[set_req][w] <= lru_age[set_req][w] + 1;
                end
                state <= RESP_WRITE;
              end
            end else begin
              // Miss: pick replacement way (prefer invalid)
              repl_way = '0;
              for (int w=0; w<ASSOC; w=w+1) begin
                if (!cache_mem[set_req][w].valid) begin
                  repl_way = w;
                  break;
                end
              end
              chosen_way <= repl_way;
              // if victim is valid and dirty => writeback first
              if (cache_mem[set_req][chosen_way].valid && cache_mem[set_req][chosen_way].dirty) begin
                state <= WB_WRITEBACK;
              end else begin
                // issue AXI read to L3 (allocate)
                saved_req_addr <= {s_req_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
                state <= ALLOC_READ;
              end
            end
          end
        end

        WB_WRITEBACK: begin
          // Drive m_aw/m_w via combinational assigns; wait for both ready
          if (m_awready && m_wready) begin
            // after AW/W accepted, wait for B
            state <= AXI_WAIT_B;
          end
        end

        AXI_WAIT_B: begin
          if (m_bvalid) begin
            // writeback acked: clear dirty, then start allocation read for original request
            cache_mem[set_req][chosen_way].dirty <= 0;
            // issue read
            saved_req_addr <= {s_req_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
            state <= ALLOC_READ;
          end
        end

        ALLOC_READ: begin
          // wait for read data from m_rvalid
          if (m_rvalid) begin
            // fill chosen way with returned word (LINE_WORDS==1 simplification)
            cache_mem[set_req][chosen_way].data <= m_rdata;
            cache_mem[set_req][chosen_way].tag  <= tag_req;
            cache_mem[set_req][chosen_way].valid <= 1;
            cache_mem[set_req][chosen_way].dirty <= (saved_req_we ? 1 : 0); // if original request was write, mark dirty
            // return data for read or complete write
            if (!saved_req_we) begin
              s_rsp_rdata <= m_rdata;
              state <= RESP_READ;
            end else begin
              // for write-allocate, write the wdata into the filled line
              cache_mem[set_req][chosen_way].data <= saved_req_wdata;
              cache_mem[set_req][chosen_way].dirty <= 1;
              state <= RESP_WRITE;
            end
          end
        end

        RESP_READ: begin
          // wait for upstream to accept response
          if (s_rsp_valid && s_rsp_ready) begin
            // update LRU ages: chosen_way becomes MRU
            for (int w=0; w<ASSOC; w=w+1) begin
              if (w == (req_hit ? req_hit_way : chosen_way)) lru_age[set_req][w] <= 0;
              else lru_age[set_req][w] <= lru_age[set_req][w] + 1;
            end
            state <= IDLE;
            s_rsp_rdata <= '0;
          end
        end

        RESP_WRITE: begin
          // write response (ack) to upstream
          if (s_rsp_valid && s_rsp_ready) begin
            // update LRU ages: chosen or hit way becomes MRU
            logic [$clog2(ASSOC)-1:0] wayidx;
            wayidx = (req_hit ? req_hit_way : chosen_way);
            for (int w=0; w<ASSOC; w=w+1) begin
              if (w == wayidx) lru_age[set_req][w] <= 0;
              else lru_age[set_req][w] <= lru_age[set_req][w] + 1;
            end
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
