`timescale 1ns/1ps
module regfile (
  input  logic           clk,
  input  logic           rst_n,
  // write port
  input  logic           we,
  input  logic [3:0]     waddr,
  input  logic [31:0]    wdata,
  // read ports
  input  logic [3:0]     raddr1,
  input  logic [3:0]     raddr2,
  output logic [31:0]    rdata1,
  output logic [31:0]    rdata2
);
  logic [31:0] regs [0:15];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      integer i;
      for (i=0;i<16;i=i+1) regs[i] <= 32'd0;
    end else begin
      if (we && waddr != 4'd0) begin
        regs[waddr] <= wdata;
      end
    end
  end

  assign rdata1 = regs[raddr1];
  assign rdata2 = regs[raddr2];

endmodule
