`timescale 1ns/1ps
module alu (
  input  logic [31:0] a,
  input  logic [31:0] b,
  input  logic [3:0]  alu_op, // use cpu_defs opcodes where appropriate
  output logic [31:0] result
);
  always_comb begin
    case (alu_op)
      4'h1: result = a + b; // ADD
      4'h2: result = a + b; // ADDI (imm provided as b)
      default: result = 32'd0;
    endcase
  end
endmodule
