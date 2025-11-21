`timescale 1ns/1ps
module cpu_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic rst_n,

    // Memory interface to external memory/cache
    output logic [ADDR_WIDTH-1:0] mem_addr,
    output logic                  mem_rd,
    output logic                  mem_wr,
    output logic [DATA_WIDTH-1:0] mem_wdata,
    input  logic [DATA_WIDTH-1:0] mem_rdata,
    input  logic                  mem_ready
);

    // -------------------------
    // Pipeline registers
    logic [ADDR_WIDTH-1:0] pc;
    logic [ADDR_WIDTH-1:0] if_pc;
    logic [31:0]           instr_if, instr_id;
    logic [31:0]           regfile [0:31];

    logic [ADDR_WIDTH-1:0] alu_ex;
    logic [DATA_WIDTH-1:0] mem_wdata_ex, mem_rdata_wb;

    logic stall;

    // -------------------------
    // Cache interface signals
    logic [ADDR_WIDTH-1:0] cpu_addr;
    logic                  cpu_rd;
    logic                  cpu_wr;
    logic [DATA_WIDTH-1:0] cpu_wdata;
    logic [DATA_WIDTH-1:0] cpu_rdata;
    logic                  cpu_ready;

    // -------------------------
    // Instantiate cache
    cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_SETS(64),
        .ASSOC(4),
        .LINE_SIZE(4),
        .REPL_LRU(1),
        .WRITE_BACK(1)
    ) cpu_cache (
        .clk(clk),
        .rst_n(rst_n),

        // CPU side
        .cpu_addr(cpu_addr),
        .cpu_rd(cpu_rd),
        .cpu_wr(cpu_wr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),

        // Memory side
        .mem_addr(mem_addr),
        .mem_rd(mem_rd),
        .mem_wr(mem_wr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    // -------------------------
    // IF Stage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_pc <= 0;
            stall <= 0;
        end else if (!stall) begin
            cpu_addr <= pc;
            cpu_rd   <= 1'b1;
            cpu_wr   <= 1'b0;
            if (!cpu_ready) begin
                stall <= 1;
            end else begin
                instr_if <= cpu_rdata;
                if_pc <= pc;
                pc <= pc + 4;
                stall <= 0;
            end
        end
    end

    // -------------------------
    // ID Stage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instr_id <= 0;
        end else if (!stall) begin
            instr_id <= instr_if;
            // Decode logic here (simplified)
        end
    end

    // -------------------------
    // EX Stage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_ex <= 0;
            mem_wdata_ex <= 0;
        end else if (!stall) begin
            // ALU operation (simplified)
            alu_ex <= regfile[instr_id[19:15]] + regfile[instr_id[24:20]];
            mem_wdata_ex <= regfile[instr_id[24:20]];
        end
    end

    // -------------------------
    // MEM Stage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset
        end else if (!stall) begin
            if (instr_id[6:0] == 7'b0000011) begin // load
                cpu_addr <= alu_ex;
                cpu_rd   <= 1'b1;
                cpu_wr   <= 1'b0;
                stall <= !cpu_ready;
            end else if (instr_id[6:0] == 7'b0100011) begin // store
                cpu_addr  <= alu_ex;
                cpu_wdata <= mem_wdata_ex;
                cpu_rd    <= 1'b0;
                cpu_wr    <= 1'b1;
                stall <= !cpu_ready;
            end else begin
                stall <= 0;
            end
        end
    end

    // -------------------------
    // WB Stage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_rdata_wb <= 0;
        end else if (!stall) begin
            if (instr_id[6:0] == 7'b0000011) begin // load
                regfile[instr_id[11:7]] <= cpu_rdata;
            end else begin
                regfile[instr_id[11:7]] <= alu_ex;
            end
        end
    end

endmodule
