`timescale 1ns/1ps
// mini_gpu_top.sv
// Top-level Mini-GPU: warp scheduler + vector ALU + AXI master bridge
module mini_gpu_top #(
  parameter int XLEN = 32,
  parameter int LANES = 4,             // SIMD lanes
  parameter int VREGS = 32,            // number of vector registers
  parameter int VREG_WIDTH = 32,       // bits per lane
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  input  logic                     clk,
  input  logic                     rst_n,

  // Simple command interface (from CPU / host)
  input  logic                     start,          // pulse to start a kernel/work
  input  logic [31:0]              kernel_id,      // small kernel identifier
  input  logic [31:0]              work_items,     // number of work items to run
  output logic                     busy,           // high while GPU running
  output logic                     done,           // pulse when kernel complete

  // AXI4-lite master (single-beat) downstream to L2/L3
  output logic [ADDR_WIDTH-1:0]    m_araddr,
  output logic                     m_arvalid,
  input  logic                     m_arready,
  input  logic [DATA_WIDTH-1:0]    m_rdata,
  input  logic                     m_rvalid,
  output logic                     m_rready,

  output logic [ADDR_WIDTH-1:0]    m_awaddr,
  output logic                     m_awvalid,
  input  logic                     m_awready,
  output logic [DATA_WIDTH-1:0]    m_wdata,
  output logic [DATA_WIDTH/8-1:0]  m_wstrb,
  output logic                     m_wvalid,
  input  logic                     m_wready,
  input  logic                     m_bvalid,
  output logic                     m_bready
);

  // Internal control/status
  logic scheduler_busy;
  logic scheduler_done;
  logic [31:0] issued_items;
  logic [31:0] completed_items;

  // Vector register file interface
  logic vreg_rd_valid;
  logic [$clog2(VREGS)-1:0] vreg_rd_idx;
  logic [VREG_WIDTH-1:0]    vreg_rd_data [LANES-1:0];
  logic vreg_rd_ready;

  logic vreg_wr_valid;
  logic [$clog2(VREGS)-1:0] vreg_wr_idx;
  logic [VREG_WIDTH-1:0]    vreg_wr_data [LANES-1:0];
  logic vreg_wr_ready;

  // Memory interface requests from vector ALU (streamlined)
  logic mem_req_valid;
  logic mem_req_is_write;
  logic [ADDR_WIDTH-1:0] mem_req_addr;
  logic [DATA_WIDTH-1:0] mem_req_wdata;
  logic [DATA_WIDTH/8-1:0] mem_req_wstrb;
  logic mem_req_ready;
  logic [DATA_WIDTH-1:0] mem_resp_rdata;
  logic mem_resp_valid;
  logic mem_resp_ready;

  // Instantiate warp scheduler
  warp_scheduler #(
    .LANES(LANES)
  ) warp_sched (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .kernel_id(kernel_id),
    .work_items(work_items),
    .busy(scheduler_busy),
    .done(scheduler_done),
    .issue_valid(mem_req_valid),
    .issue_addr(mem_req_addr),
    .issue_is_write(mem_req_is_write),
    .issue_wdata(mem_req_wdata),
    .issue_wstrb(mem_req_wstrb),
    .issue_ready(mem_req_ready),
    .completed_items(completed_items)
  );

  // Instantiate vector register file
  vregfile #(
    .LANES(LANES),
    .VREGS(VREGS),
    .VREG_WIDTH(VREG_WIDTH)
  ) vregs (
    .clk(clk),
    .rst_n(rst_n),
    .rd_valid(vreg_rd_valid),
    .rd_idx(vreg_rd_idx),
    .rd_data(vreg_rd_data),
    .rd_ready(vreg_rd_ready),
    .wr_valid(vreg_wr_valid),
    .wr_idx(vreg_wr_idx),
    .wr_data(vreg_wr_data),
    .wr_ready(vreg_wr_ready)
  );

  // Instantiate vector ALU
  vector_alu #(
    .LANES(LANES),
    .DATA_WIDTH(VREG_WIDTH)
  ) valu (
    .clk(clk),
    .rst_n(rst_n),
    .start(scheduler_busy),
    // vreg interface
    .vreg_rd_valid(vreg_rd_valid),
    .vreg_rd_idx(vreg_rd_idx),
    .vreg_rd_data(vreg_rd_data),
    .vreg_rd_ready(vreg_rd_ready),

    .vreg_wr_valid(vreg_wr_valid),
    .vreg_wr_idx(vreg_wr_idx),
    .vreg_wr_data(vreg_wr_data),
    .vreg_wr_ready(vreg_wr_ready),

    // memory interface (simple)
    .mem_req_valid(mem_req_valid),
    .mem_req_is_write(mem_req_is_write),
    .mem_req_addr(mem_req_addr),
    .mem_req_wdata(mem_req_wdata),
    .mem_req_wstrb(mem_req_wstrb),
    .mem_req_ready(mem_req_ready),
    .mem_resp_rdata(mem_resp_rdata),
    .mem_resp_valid(mem_resp_valid),
    .mem_resp_ready(mem_resp_ready)
  );

  // AXI master bridge: convert mem_req_* to AXI single-beat
  axi_master_bridge #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) axi_bridge (
    .clk(clk),
    .rst_n(rst_n),

    // simplified memory req interface
    .req_valid(mem_req_valid),
    .req_is_write(mem_req_is_write),
    .req_addr(mem_req_addr),
    .req_wdata(mem_req_wdata),
    .req_wstrb(mem_req_wstrb),
    .req_ready(mem_req_ready),
    .resp_rdata(mem_resp_rdata),
    .resp_valid(mem_resp_valid),
    .resp_ready(mem_resp_ready),

    // AXI master ports
    .m_araddr(m_araddr),
    .m_arvalid(m_arvalid),
    .m_arready(m_arready),
    .m_rdata(m_rdata),
    .m_rvalid(m_rvalid),
    .m_rready(m_rready),

    .m_awaddr(m_awaddr),
    .m_awvalid(m_awvalid),
    .m_awready(m_awready),
    .m_wdata(m_wdata),
    .m_wstrb(m_wstrb),
    .m_wvalid(m_wvalid),
    .m_wready(m_wready),
    .m_bvalid(m_bvalid),
    .m_bready(m_bready)
  );

  // Top-level busy/done signals
  assign busy = scheduler_busy;
  assign done = scheduler_done;

endmodule
