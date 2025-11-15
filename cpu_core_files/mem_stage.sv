`timescale 1ns/1ps
module mem_stage (
  input  logic         clk,
  input  logic         rst_n,
  // inputs from EX
  input  logic [3:0]   rd_in,
  input  logic [3:0]   op_in,
  input  logic [31:0]  alu_in,
  input  logic [31:0]  store_data_in,
  input  logic         mem_read_in,
  input  logic         mem_write_in,
  input  logic         valid_in,
  // memory interface
  output logic [31:0]  dmem_addr,
  output logic         dmem_rd,
  output logic         dmem_wr,
  output logic [31:0]  dmem_wdata,
  input  logic [31:0]  dmem_rdata,
  input  logic         dmem_ready,
  // outputs to WB
  output logic [3:0]   rd_out,
  output logic [31:0]  mem_data_out,
  output logic [31:0]  alu_out,
  output logic         valid_out
);
  assign dmem_addr = alu_in;
  assign dmem_rd = mem_read_in;
  assign dmem_wr = mem_write_in;
  assign dmem_wdata = store_data_in;

  // If read, pass mem_rdata else pass alu_in as result
  assign mem_data_out = dmem_rdata;
  assign alu_out = alu_in;
  assign rd_out = rd_in;
  assign valid_out = valid_in & (dmem_ready | ~mem_read_in);

endmodule
