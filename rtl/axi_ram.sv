`timescale 1ns/1ps
// axi_ram_model.sv - simple AXI4-lite slave RAM model (single-beat reads/writes)
// - memory depth in words
module axi_ram_model #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32,
  parameter DEPTH_WORDS = 16384,
  parameter LATENCY_CYCLES = 2
)(
  input  logic                   clk,
  input  logic                   rst_n,
  // AR channel
  input  logic [ADDR_WIDTH-1:0]  araddr,
  input  logic                   arvalid,
  output logic                   arready,
  output logic [DATA_WIDTH-1:0]  rdata,
  output logic                   rvalid,
  input  logic                   rready,
  // AW/W/B channels
  input  logic [ADDR_WIDTH-1:0]  awaddr,
  input  logic                   awvalid,
  output logic                   awready,
  input  logic [DATA_WIDTH-1:0]  wdata,
  input  logic [DATA_WIDTH/8-1:0] wstrb,
  input  logic                   wvalid,
  output logic                   wready,
  output logic                   bvalid,
  input  logic                   bready
);

  // simple memory
  logic [DATA_WIDTH-1:0] mem [0:DEPTH_WORDS-1];

  // compute index
  wire [$clog2(DEPTH_WORDS)-1:0] read_idx = araddr[$clog2(DEPTH_WORDS)+1:2];
  wire [$clog2(DEPTH_WORDS)-1:0] write_idx = awaddr[$clog2(DEPTH_WORDS)+1:2];

  // ready signals: accept address immediately
  assign arready = 1'b1;
  assign awready = 1'b1;
  assign wready  = 1'b1;

  // read path with latency
  integer rd_count;
  reg [DATA_WIDTH-1:0] rd_buffer;
  reg [31:0] rd_timer;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rvalid <= 0;
      rd_timer <= 0;
    end else begin
      if (arvalid && arready) begin
        rd_timer <= LATENCY_CYCLES;
        rd_buffer <= mem[read_idx];
      end
      if (rd_timer > 0) rd_timer <= rd_timer - 1;
      if (rd_timer == 1) begin
        rdata <= rd_buffer;
        rvalid <= 1;
      end
      if (rvalid && rready) rvalid <= 0;
    end
  end

  // write path: accept and update memory immediately, then assert bvalid next cycle
  reg bvalid_r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bvalid_r <= 0;
      bvalid <= 0;
    end else begin
      bvalid <= bvalid_r;
      if (awvalid && wvalid) begin
        // apply write strobe
        for (int byte=0; byte<DATA_WIDTH/8; byte=byte+1) begin
          if (wstrb[byte]) begin
            // write that byte
            mem[write_idx][8*byte +: 8] <= wdata[8*byte +: 8];
          end
        end
        bvalid_r <= 1;
      end else if (bvalid && bready) begin
        bvalid_r <= 0;
      end
    end
  end

endmodule
