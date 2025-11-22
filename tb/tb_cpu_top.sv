// tb_cpu_top.sv
`timescale 1ns/1ps

module tb_cpu_top;

  parameter int XLEN = 32;
  
  // Clock and reset
  logic clk;
  logic rst_n;

  // AXI signals
  logic [XLEN-1:0] axi_awaddr;
  logic axi_awvalid;
  logic axi_awready;

  logic [XLEN-1:0] axi_araddr;
  logic axi_arvalid;
  logic axi_arready;

  logic [XLEN-1:0] axi_wdata;
  logic [3:0] axi_wstrb;
  logic axi_wvalid;
  logic axi_wready;

  logic [XLEN-1:0] axi_rdata;
  logic axi_rvalid;
  logic axi_rready;

  logic axi_bvalid;
  logic axi_bready;

  // Clock generation
  initial clk = 0;
  always #5 clk = ~clk; // 100 MHz

  // Reset pulse
  initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
  end

  // Instantiate DUT
  cpu_top #(
    .XLEN(XLEN)
  ) DUT (
    .clk(clk),
    .rst_n(rst_n),
    .axi_awaddr(axi_awaddr),
    .axi_awvalid(axi_awvalid),
    .axi_awready(axi_awready),
    .axi_araddr(axi_araddr),
    .axi_arvalid(axi_arvalid),
    .axi_arready(axi_arready),
    .axi_wdata(axi_wdata),
    .axi_wstrb(axi_wstrb),
    .axi_wvalid(axi_wvalid),
    .axi_wready(axi_wready),
    .axi_rdata(axi_rdata),
    .axi_rvalid(axi_rvalid),
    .axi_rready(axi_rready),
    .axi_bvalid(axi_bvalid),
    .axi_bready(axi_bready)
  );

  // AXI Stub / Simple memory model
  initial begin
    axi_awready = 0;
    axi_wready  = 0;
    axi_bvalid  = 0;

    axi_arready = 0;
    axi_rvalid  = 0;
    axi_rdata   = 0;

    forever begin
      @(posedge clk);
      // Write handshake
      axi_awready <= axi_awvalid;
      axi_wready  <= axi_wvalid;
      axi_bvalid  <= axi_awvalid & axi_wvalid;
      // Read handshake
      axi_arready <= axi_arvalid;
      axi_rvalid  <= axi_arvalid;
      axi_rdata   <= axi_araddr + 32'h1000; // dummy read data
    end
  end

  // Optional: stop simulation after some time
  initial begin
    #1000;
    $finish;
  end

  // Enable VCD waveform
  initial begin
    $dumpfile("tb_cpu_top.vcd");
    $dumpvars(0, tb_cpu_top);
  end

endmodule
