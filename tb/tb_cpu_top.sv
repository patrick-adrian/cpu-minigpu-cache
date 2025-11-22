`timescale 1ns/1ps
//OG CPU_top, no cache, axi
module tb_cpu_top;

  // ----------------------------------------
  // Clock + Reset
  // ----------------------------------------
  logic clk;
  logic reset_n;

  // DUT interface
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;

  logic        dmem_read;
  logic        dmem_write;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [31:0] dmem_rdata;

  // Simple instruction + data memories
  logic [31:0] instr_mem [0:255];
  logic [31:0] data_mem  [0:255];

  // ----------------------------------------
  // Clock generation (10 ns)
  // ----------------------------------------
  always #5 clk = ~clk;

  // ----------------------------------------
  // DUT
  // ----------------------------------------
  cpu_top dut (
      .clk(clk),
      .reset_n(reset_n),

      // Instruction fetch
      .imem_addr(imem_addr),
      .imem_rdata(imem_rdata),

      // Data memory
      .dmem_read(dmem_read),
      .dmem_write(dmem_write),
      .dmem_addr(dmem_addr),
      .dmem_wdata(dmem_wdata),
      .dmem_rdata(dmem_rdata)
  );

  // ----------------------------------------
  // Instruction Memory Model
  // ----------------------------------------
  assign imem_rdata = instr_mem[imem_addr[9:2]];

  // ----------------------------------------
  // Data Memory Model
  // ----------------------------------------
  always_ff @(posedge clk) begin
    if (dmem_write)
      data_mem[dmem_addr[9:2]] <= dmem_wdata;
  end

  assign dmem_rdata = (dmem_read) ? data_mem[dmem_addr[9:2]] : 32'h0;


  // ----------------------------------------
  // Test Program Loader
  // ----------------------------------------
  task load_program;
    begin
      // Simple ADD test:
      // x1 = 5
      // x2 = 7
      // x3 = x1 + x2  => should be 12

      instr_mem[0] = 32'h00500093; // ADDI x1, x0, 5
      instr_mem[1] = 32'h00700113; // ADDI x2, x0, 7
      instr_mem[2] = 32'h002081B3; // ADD x3, x1, x2
      instr_mem[3] = 32'h00000013; // NOP
      instr_mem[4] = 32'h00000013; // NOP
      instr_mem[5] = 32'h00000013; // NOP
    end
  endtask

  // ----------------------------------------
  // Test Sequence
  // ----------------------------------------
  initial begin
    clk = 0;
    reset_n = 0;

    // Clear memories
    foreach (instr_mem[i]) instr_mem[i] = 32'h00000013; // NOP
    foreach (data_mem[i])  data_mem[i]  = 32'h0;

    load_program();

    repeat (5) @(posedge clk);
    reset_n = 1;

    // Run CPU for some cycles
    repeat (50) @(posedge clk);

    // Check result of x3 (should be 12)
    $display("Register x3 = %0d (expected 12)", dut.regfile.regs[3]);

    if (dut.regfile.regs[3] == 12)
      $display("TEST PASS");
    else
      $display("TEST FAIL");

    $finish;
  end

endmodule
