`timescale 1ns/1ps
// warp_scheduler.sv
// Very small scheduler: issues sequential memory ops as "work"
// For simplicity scheduler generates a stream of mem requests (loads/stores) that vector ALU consumes.
module warp_scheduler #(
  parameter int LANES = 4
)(
  input  logic              clk,
  input  logic              rst_n,
  input  logic              start,
  input  logic [31:0]       kernel_id,
  input  logic [31:0]       work_items,
  output logic              busy,
  output logic              done,

  // issue stream (to AXI bridge)
  output logic              issue_valid,
  output logic [31:0]       issue_addr,
  output logic              issue_is_write,
  output logic [31:0]       issue_wdata,
  output logic [3:0]        issue_wstrb,
  input  logic              issue_ready,

  output logic [31:0]      completed_items
);

  typedef enum logic [1:0] {IDLE, ISSUING, WAIT_DONE} st_t;
  st_t state, next_state;

  logic [31:0] counter;
  logic [31:0] issued_count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      counter <= 0;
      issued_count <= 0;
      completed_items <= 0;
    end else begin
      case (state)
        IDLE: begin
          if (start) begin
            state <= ISSUING;
            counter <= 0;
            issued_count <= 0;
            completed_items <= 0;
          end
        end
        ISSUING: begin
          if (counter < work_items) begin
            if (issue_ready) begin
              // issue a request: for demo, alternate read/write per item
              issued_count <= issued_count + 1;
              counter <= counter + 1;
            end
          end else begin
            state <= WAIT_DONE;
          end
        end
        WAIT_DONE: begin
          // for simplicity assume completion is immediate -- set done when issued_count hits work_items
          if (issued_count == work_items) begin
            completed_items <= issued_count;
            state <= IDLE;
          end
        end
      endcase
    end
  end

  // Issue outputs (combinational, simple addresses)
  assign issue_valid = (state == ISSUING) && (counter < work_items);
  assign issue_addr  = 32'h8000_0000 + counter*4; // example base address
  assign issue_is_write = 1'b0; // keep read-only for now
  assign issue_wdata = 32'h0;
  assign issue_wstrb = 4'hF;

  assign busy = (state != IDLE);
  assign done = (state == IDLE && completed_items == work_items);

endmodule
