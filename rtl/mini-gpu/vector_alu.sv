`timescale 1ns/1ps
// vector_alu.sv
// Simple SIMD vector ALU which can read vector registers and produce outputs.
// For this minimal implementation the ALU performs an elementwise add of a loaded memory vector into a target vreg.
module vector_alu #(
  parameter int LANES = 4,
  parameter int DATA_WIDTH = 32
)(
  input  logic                     clk,
  input  logic                     rst_n,
  input  logic                     start,

  // vreg read port
  output logic                     vreg_rd_valid,
  output logic [$clog2(32)-1:0]    vreg_rd_idx,  // use 32 vregs default; actual indexing handled by top
  input  logic [DATA_WIDTH-1:0]    vreg_rd_data [LANES-1:0],
  input  logic                     vreg_rd_ready,

  // vreg write port
  output logic                     vreg_wr_valid,
  output logic [$clog2(32)-1:0]    vreg_wr_idx,
  output logic [DATA_WIDTH-1:0]    vreg_wr_data [LANES-1:0],
  input  logic                     vreg_wr_ready,

  // simple memory request interface (from scheduler)
  input  logic                     mem_req_valid,
  input  logic                     mem_req_is_write,
  input  logic [31:0]              mem_req_addr,
  input  logic [31:0]              mem_req_wdata,
  input  logic [3:0]               mem_req_wstrb,
  output logic                     mem_req_ready,

  input  logic [31:0]              mem_resp_rdata,
  input  logic                     mem_resp_valid,
  output logic                     mem_resp_ready
);

  // For this minimal ALU, we simply forward memory responses into vreg writes.
  // Behavior:
  // - When mem_resp_valid presents a word, write that word into vreg[0] lane0..laneN-1 (replicated)
  // - This is a toy implementation you can expand later.

  assign mem_req_ready = 1'b1;
  assign mem_resp_ready = 1'b1;

  // simple pass-through: whenever mem_resp_valid, create a vreg write
  assign vreg_wr_valid = mem_resp_valid;
  assign vreg_wr_idx = '0; // write into vreg 0 for now

  genvar g;
  generate
    for (g=0; g<LANES; g=g+1) begin : mk_wrdata
      assign vreg_wr_data[g] = mem_resp_rdata; // replicate across lanes as a simple example
    end
  endgenerate

  // no reads in this minimal ALU
  assign vreg_rd_valid = 1'b0;
  assign vreg_rd_idx = '0;

endmodule
