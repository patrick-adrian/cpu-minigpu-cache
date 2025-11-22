`timescale 1ns/1ps
// vregfile.sv - very small vector register file
module vregfile #(
  parameter int LANES = 4,
  parameter int VREGS = 32,
  parameter int VREG_WIDTH = 32
)(
  input  logic                    clk,
  input  logic                    rst_n,

  // read port (combinational or one-cycle)
  input  logic                    rd_valid,
  input  logic [$clog2(VREGS)-1:0] rd_idx,
  output logic [VREG_WIDTH-1:0]   rd_data [LANES-1:0],
  output logic                    rd_ready,

  // write port (single-cycle write on valid)
  input  logic                    wr_valid,
  input  logic [$clog2(VREGS)-1:0] wr_idx,
  input  logic [VREG_WIDTH-1:0]   wr_data [LANES-1:0],
  output logic                    wr_ready
);

  // banked register array: vreg[regnum][lane]
  logic [VREG_WIDTH-1:0] regs [0:VREGS-1][0:LANES-1];

  // read logic (combinational)
  assign rd_ready = 1'b1;
  genvar i;
  generate
    for (i=0; i<LANES; i=i+1) begin : rdport
      assign rd_data[i] = regs[rd_idx][i];
    end
  endgenerate

  // write logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int r=0; r<VREGS; r=r+1)
        for (int l=0; l<LANES; l=l+1)
          regs[r][l] <= '0;
      wr_ready <= 1'b1;
    end else begin
      if (wr_valid) begin
        for (int l=0; l<LANES; l=l+1) regs[wr_idx][l] <= wr_data[l];
      end
      wr_ready <= 1'b1;
    end
  end

endmodule
