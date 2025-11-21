`timescale 1ns/1ps
module ex_stage (
  input  logic         clk,
  input  logic         rst_n,
  // inputs from ID
  input  logic [3:0]   rd_in,
  input  logic [3:0]   op_in,
  input  logic [31:0]  imm_in,
  input  logic [31:0]  rs1_in,
  input  logic [31:0]  rs2_in,
  input  logic         valid_in,
  // outputs to MEM
  output logic [3:0]   rd_out,
  output logic [3:0]   op_out,
  output logic [31:0]  alu_result,
  output logic [31:0]  store_data,
  output logic         mem_read,
  output logic         mem_write,
  output logic         valid_out
);
  import cpu_defs_pkg::*;
  // ALU: simple add for ADD/ADDI
  always_comb begin
    alu_result = 32'd0;
    mem_read = 1'b0;
    mem_write = 1'b0;
    store_data = rs2_in;
    case (op_in)
      OP_ADD:   alu_result = rs1_in + rs2_in;
      OP_ADDI:  alu_result = rs1_in + imm_in;
      OP_LOAD:  begin alu_result = rs1_in + imm_in; mem_read = 1'b1; end
      OP_STORE: begin alu_result = rs1_in + imm_in; mem_write = 1'b1; end
      default: alu_result = 32'd0;
    endcase
  end

  assign rd_out = rd_in;
  assign op_out = op_in;
  assign valid_out = valid_in;

endmodule
