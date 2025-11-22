`timescale 1ns/1ps
module wb_stage (
  input  logic         clk,
  input  logic         rst_n,
  // inputs from MEM
  input  logic [3:0]   rd_in,
  input  logic [3:0]   op_in,
  input  logic [31:0]  mem_data_in,
  input  logic [31:0]  alu_in,
  input  logic         valid_in,
  // regfile write port
  output logic         rf_we,
  output logic [3:0]   rf_waddr,
  output logic [31:0]  rf_wdata,
  output logic         halted
);
  import cpu_defs_pkg::*;
  always_comb begin
    rf_we = 1'b0;
    rf_waddr = rd_in;
    rf_wdata = 32'd0;
    halted = 1'b0;
    if (valid_in) begin
      case (op_in)
        OP_ADD, OP_ADDI: begin rf_we = 1'b1; rf_wdata = alu_in; end
        OP_LOAD:         begin rf_we = 1'b1; rf_wdata = mem_data_in; end
        OP_HALT:         begin halted = 1'b1; end
        default: begin end
      endcase
    end
  end
endmodule
