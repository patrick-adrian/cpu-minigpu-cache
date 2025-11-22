`timescale 1ns/1ps
// axi_master_bridge.sv - simple single-beat AXI master bridge
// Converts simple memory request interface to AXI4-lite single-beat transactions.
// NOTE: This is intentionally simple. Extend for bursts, outstanding ops, IDs.
module axi_master_bridge #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 32
)(
  input  logic                   clk,
  input  logic                   rst_n,

  // Simple memory request interface
  input  logic                   req_valid,
  input  logic                   req_is_write,
  input  logic [ADDR_WIDTH-1:0]  req_addr,
  input  logic [DATA_WIDTH-1:0]  req_wdata,
  input  logic [DATA_WIDTH/8-1:0] req_wstrb,
  output logic                   req_ready,
  output logic [DATA_WIDTH-1:0]  resp_rdata,
  output logic                   resp_valid,
  input  logic                   resp_ready,

  // AXI4-lite Master ports
  output logic [ADDR_WIDTH-1:0]  m_araddr,
  output logic                   m_arvalid,
  input  logic                   m_arready,
  input  logic [DATA_WIDTH-1:0]  m_rdata,
  input  logic                   m_rvalid,
  output logic                   m_rready,

  output logic [ADDR_WIDTH-1:0]  m_awaddr,
  output logic                   m_awvalid,
  input  logic                   m_awready,
  output logic [DATA_WIDTH-1:0]  m_wdata,
  output logic [DATA_WIDTH/8-1:0] m_wstrb,
  output logic                   m_wvalid,
  input  logic                   m_wready,
  input  logic                   m_bvalid,
  output logic                   m_bready
);

  typedef enum logic [2:0] {IDLE, DO_READ, WAIT_R, DO_WRITE, WAIT_B} st_t;
  st_t state;

  // registers to hold request
  logic [ADDR_WIDTH-1:0] saved_addr;
  logic [DATA_WIDTH-1:0] saved_wdata;
  logic [DATA_WIDTH/8-1:0] saved_wstrb;
  logic saved_is_write;

  assign req_ready = (state == IDLE);

  // AXI outputs driven combinationally from state and saved regs
  assign m_araddr = (state == DO_READ) ? saved_addr : '0;
  assign m_arvalid = (state == DO_READ);

  assign m_awaddr = (state == DO_WRITE) ? saved_addr : '0;
  assign m_awvalid = (state == DO_WRITE);
  assign m_wdata = (state == DO_WRITE) ? saved_wdata : '0;
  assign m_wstrb = (state == DO_WRITE) ? saved_wstrb : '0;
  assign m_wvalid = (state == DO_WRITE);

  assign m_rready = (state == WAIT_R);
  assign m_bready = (state == WAIT_B);

  // simple FSM handling single-beat read/write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      saved_addr <= '0;
      saved_wdata <= '0;
      saved_wstrb <= '0;
      saved_is_write <= 0;
    end else begin
      case (state)
        IDLE: begin
          resp_valid <= 0;
          if (req_valid) begin
            saved_addr <= req_addr;
            saved_wdata <= req_wdata;
            saved_wstrb <= req_wstrb;
            saved_is_write <= req_is_write;
            if (req_is_write) state <= DO_WRITE;
            else state <= DO_READ;
          end
        end

        DO_READ: begin
          if (m_arready) begin
            state <= WAIT_R;
          end
        end

        WAIT_R: begin
          if (m_rvalid) begin
            resp_rdata <= m_rdata;
            resp_valid <= 1;
            if (resp_ready) begin
              resp_valid <= 0;
              state <= IDLE;
            end
          end
        end

        DO_WRITE: begin
          if (m_awready && m_wready) begin
            state <= WAIT_B;
          end
        end

        WAIT_B: begin
          if (m_bvalid) begin
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
