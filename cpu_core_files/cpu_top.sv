`timescale 1ns/1ps
module cpu_top (
  input  logic        clk,
  input  logic        rst_n,
  // Instruction memory interface
  output logic [31:0] imem_addr,
  output logic        imem_rd,
  input  logic [31:0]  imem_rdata,
  input  logic         imem_ready,
  // Data memory interface
  output logic [31:0] dmem_addr,
  output logic        dmem_rd,
  output logic        dmem_wr,
  output logic [31:0] dmem_wdata,
  input  logic [31:0]  dmem_rdata,
  input  logic         dmem_ready,
  // status
  output logic        halted
);
  import cpu_defs_pkg::*;

  // IF stage
  logic [31:0] if_instr, if_pc;
  logic if_valid;

  if_stage IF (
    .clk(clk), .rst_n(rst_n), .stall(1'b0), .branch(1'b0), .branch_target(32'd0),
    .imem_addr(imem_addr), .imem_rd(imem_rd), .imem_rdata(imem_rdata), .imem_ready(imem_ready),
    .instr_out(if_instr), .pc_out(if_pc), .valid_out(if_valid)
  );

  // ID stage
  logic [3:0] raddr1, raddr2;
  logic [31:0] rdata1, rdata2;
  logic [3:0] id_rd;
  logic [3:0] id_op;
  logic [31:0] id_imm;
  logic id_valid;

  id_stage ID (
    .clk(clk), .rst_n(rst_n),
    .instr_in(if_instr), .pc_in(if_pc), .valid_in(if_valid),
    .raddr1(raddr1), .raddr2(raddr2), .rdata1(rdata1), .rdata2(rdata2),
    .rd(id_rd), .op(id_op), .imm(id_imm), .rs1_val(rdata1), .rs2_val(rdata2),
    .valid_out(id_valid)
  );

  // regfile
  logic rf_we;
  logic [3:0] rf_waddr;
  logic [31:0] rf_wdata;
  regfile RF(.clk(clk), .rst_n(rst_n), .we(rf_we), .waddr(rf_waddr), .wdata(rf_wdata),
             .raddr1(raddr1), .raddr2(raddr2), .rdata1(rdata1), .rdata2(rdata2));

  // EX stage
  logic [3:0] ex_rd;
  logic [3:0] ex_op;
  logic [31:0] ex_alu;
  logic [31:0] ex_store;
  logic ex_mem_read, ex_mem_write;
  logic ex_valid;

  ex_stage EX (.clk(clk), .rst_n(rst_n),
    .rd_in(id_rd), .op_in(id_op), .imm_in(id_imm), .rs1_in(rdata1), .rs2_in(rdata2), .valid_in(id_valid),
    .rd_out(ex_rd), .op_out(ex_op), .alu_result(ex_alu), .store_data(ex_store),
    .mem_read(ex_mem_read), .mem_write(ex_mem_write), .valid_out(ex_valid)
  );

  // MEM stage
  logic [3:0] mem_rd;
  logic [31:0] mem_data_out;
  logic [31:0] mem_alu_out;
  logic mem_valid;

  mem_stage MEM (.clk(clk), .rst_n(rst_n),
    .rd_in(ex_rd), .op_in(ex_op), .alu_in(ex_alu), .store_data_in(ex_store),
    .mem_read_in(ex_mem_read), .mem_write_in(ex_mem_write), .valid_in(ex_valid),
    .dmem_addr(dmem_addr), .dmem_rd(dmem_rd), .dmem_wr(dmem_wr), .dmem_wdata(dmem_wdata),
    .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
    .rd_out(mem_rd), .mem_data_out(mem_data_out), .alu_out(mem_alu_out), .valid_out(mem_valid)
  );

  // WB stage
  logic wb_rf_we;
  logic [3:0] wb_rf_waddr;
  logic [31:0] wb_rf_wdata;
  logic halted_local;

  wb_stage WB (.clk(clk), .rst_n(rst_n),
    .rd_in(mem_rd), .op_in(ex_op), .mem_data_in(mem_data_out), .alu_in(mem_alu_out), .valid_in(mem_valid),
    .rf_we(wb_rf_we), .rf_waddr(wb_rf_waddr), .rf_wdata(wb_rf_wdata), .halted(halted_local)
  );

  // connect WB writeback to regfile write
  assign rf_we = wb_rf_we;
  assign rf_waddr = wb_rf_waddr;
  assign rf_wdata = wb_rf_wdata;

  assign halted = halted_local;

endmodule
