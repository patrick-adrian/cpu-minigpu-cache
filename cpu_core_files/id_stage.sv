`timescale 1ns/1ps
module id_stage (
  input  logic         clk,
  input  logic         rst_n,
  // inputs from IF
  input  logic [31:0]  instr_in,
  input  logic [31:0]  pc_in,
  input  logic         valid_in,
  // register file interface
  output logic [3:0]   raddr1,
  output logic [3:0]   raddr2,
  input  logic [31:0]  rdata1,
  input  logic [31:0]  rdata2,
  // outputs to EX
  output logic [3:0]   rd,
  output logic [3:0]   op,
  output logic [31:0]  imm,
  output logic [31:0]  rs1_val,
  output logic [31:0]  rs2_val,
  output logic         valid_out
);
  import cpu_defs_pkg::*;

  logic [3:0] opcode;
  logic [3:0] rd_f;
  logic [3:0] rs1_f;
  logic [3:0] rs2_f;
  logic [15:0] imm16;

  always_comb begin
    opcode = instr_in[31:28];
    rd_f = instr_in[27:24];
    rs1_f = instr_in[23:20];
    rs2_f = instr_in[19:16];
    imm16 = instr_in[15:0];
  end

  assign raddr1 = rs1_f;
  assign raddr2 = rs2_f;
  assign rd = rd_f;
  assign op = opcode;
  assign imm = {{16{imm16[15]}}, imm16}; // sign-extend
  assign rs1_val = rdata1;
  assign rs2_val = rdata2;
  assign valid_out = valid_in;

endmodule
