`timescale 1ns/1ps
module if_stage (
  input  logic         clk,
  input  logic         rst_n,
  // control
  input  logic         stall,
  input  logic         branch,
  input  logic [31:0]  branch_target,
  // instruction memory interface
  output logic [31:0]  imem_addr,
  output logic         imem_rd,
  input  logic [31:0]  imem_rdata,
  input  logic         imem_ready,
  // outputs to ID
  output logic [31:0]  instr_out,
  output logic [31:0]  pc_out,
  output logic         valid_out
);
  logic [31:0] pc;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc <= 32'h0000_0000;
    end else if (!stall) begin
      if (branch) pc <= branch_target;
      else pc <= pc + 4;
    end
  end

  assign imem_addr = pc;
  assign imem_rd = 1'b1; // always fetch
  assign instr_out = imem_rdata;
  assign pc_out = pc;
  assign valid_out = imem_ready; // treat ready as valid indicator

endmodule
