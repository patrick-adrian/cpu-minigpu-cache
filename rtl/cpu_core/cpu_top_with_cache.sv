//===========================================================
// cpu_top.sv  (CPU + L1 Instruction Cache + L1 Data Cache)
//===========================================================

module cpu_top #(
    parameter int XLEN = 32
)(
    input  logic               clk,
    input  logic               rst_n,

    // AXI Master Interface to L2
    output logic [XLEN-1:0]    axi_awaddr,
    output logic               axi_awvalid,
    input  logic               axi_awready,

    output logic [XLEN-1:0]    axi_araddr,
    output logic               axi_arvalid,
    input  logic               axi_arready,

    output logic [XLEN-1:0]    axi_wdata,
    output logic [3:0]         axi_wstrb,
    output logic               axi_wvalid,
    input  logic               axi_wready,

    input  logic [XLEN-1:0]    axi_rdata,
    input  logic               axi_rvalid,
    output logic               axi_rready,

    input  logic               axi_bvalid,
    output logic               axi_bready
);

    //===========================
    // Pipeline Interconnect Wires
    //===========================

    // IF → ID
    logic [XLEN-1:0] if_pc, if_instr;
    logic            if_valid;

    // ID → EX
    logic [XLEN-1:0] id_rs1, id_rs2, id_imm, id_pc;
    logic [4:0]      id_rd;
    logic            id_regwrite, id_memread, id_memwrite, id_branch;
    logic [3:0]      id_aluop;

    // EX → MEM
    logic [XLEN-1:0] ex_alu_res, ex_rs2_fwd;
    logic [4:0]      ex_rd;
    logic            ex_regwrite, ex_memread, ex_memwrite;

    // MEM → WB
    logic [XLEN-1:0] mem_data_out, mem_alu_res;
    logic [4:0]      mem_rd;
    logic            mem_regwrite;

    //===========================
    // L1 Instruction Cache
    //===========================

    logic              icache_req_valid;
    logic [XLEN-1:0]   icache_req_addr;

    logic              icache_rsp_valid;
    logic [31:0]       icache_rsp_instr;

    // I-Cache → AXI signals
    logic [XLEN-1:0]   icache_axi_araddr;
    logic              icache_axi_arvalid;
    logic              icache_axi_arready_int;

    logic [XLEN-1:0]   icache_axi_rdata;
    logic              icache_axi_rvalid;
    logic              icache_axi_rready;

    icache_L1 #(
        .XLEN(XLEN)
    ) i_icache (
        .clk(clk),
        .rst_n(rst_n),

        .req_valid(icache_req_valid),
        .req_addr(icache_req_addr),

        .rsp_valid(icache_rsp_valid),
        .rsp_instr(icache_rsp_instr),

        // AXI Read-only subset (instruction fetch)
        .axi_araddr(icache_axi_araddr),
        .axi_arvalid(icache_axi_arvalid),
        .axi_arready(icache_axi_arready_int),

        .axi_rdata(icache_axi_rdata),
        .axi_rvalid(icache_axi_rvalid),
        .axi_rready(icache_axi_rready)
    );

    //===========================
    // L1 Data Cache
    //===========================

    logic              dcache_req_valid;
    logic [XLEN-1:0]   dcache_req_addr;
    logic [XLEN-1:0]   dcache_req_wdata;
    logic [3:0]        dcache_req_wstrb;
    logic              dcache_req_we;

    logic              dcache_rsp_valid;
    logic [XLEN-1:0]   dcache_rsp_rdata;

    // D-Cache → AXI (read + write)
    logic [XLEN-1:0] dcache_axi_araddr;
    logic            dcache_axi_arvalid;
    logic            dcache_axi_arready_int;

    logic [XLEN-1:0] dcache_axi_awaddr;
    logic            dcache_axi_awvalid;
    logic            dcache_axi_awready_int;

    logic [XLEN-1:0] dcache_axi_wdata;
    logic [3:0]      dcache_axi_wstrb;
    logic            dcache_axi_wvalid;
    logic            dcache_axi_wready_int;

    logic [XLEN-1:0] dcache_axi_rdata;
    logic            dcache_axi_rvalid;
    logic            dcache_axi_rready;

    logic            dcache_axi_bvalid;
    logic            dcache_axi_bready;

    dcache_L1 #(
        .XLEN(XLEN)
    ) i_dcache (
        .clk(clk),
        .rst_n(rst_n),

        .req_valid(dcache_req_valid),
        .req_addr(dcache_req_addr),
        .req_wdata(dcache_req_wdata),
        .req_wstrb(dcache_req_wstrb),
        .req_we(dcache_req_we),

        .rsp_valid(dcache_rsp_valid),
        .rsp_rdata(dcache_rsp_rdata),

        // AXI read + write
        .axi_araddr(dcache_axi_araddr),
        .axi_arvalid(dcache_axi_arvalid),
        .axi_arready(dcache_axi_arready_int),

        .axi_awaddr(dcache_axi_awaddr),
        .axi_awvalid(dcache_axi_awvalid),
        .axi_awready(dcache_axi_awready_int),

        .axi_wdata(dcache_axi_wdata),
        .axi_wstrb(dcache_axi_wstrb),
        .axi_wvalid(dcache_axi_wvalid),
        .axi_wready(dcache_axi_wready_int),

        .axi_rdata(dcache_axi_rdata),
        .axi_rvalid(dcache_axi_rvalid),
        .axi_rready(dcache_axi_rready),

        .axi_bvalid(dcache_axi_bvalid),
        .axi_bready(dcache_axi_bready)
    );

    //======================================================
    // Shared AXI Arbiter (Simple Priority: D-Cache > I-Cache)
    //======================================================

    assign axi_araddr  = dcache_axi_arvalid ? dcache_axi_araddr  : icache_axi_araddr;
    assign axi_arvalid = dcache_axi_arvalid ? 1'b1               : icache_axi_arvalid;
    assign icache_axi_arready_int = axi_arready & ~dcache_axi_arvalid;
    assign dcache_axi_arready_int = axi_arready &  dcache_axi_arvalid;

    assign axi_rready = dcache_axi_arvalid ? dcache_axi_rready : icache_axi_rready;
    assign icache_axi_rdata  = axi_rdata;
    assign dcache_axi_rdata  = axi_rdata;
    assign icache_axi_rvalid = axi_rvalid & ~dcache_axi_arvalid;
    assign dcache_axi_rvalid = axi_rvalid &  dcache_axi_arvalid;

    // Write Path (only D-cache writes)
    assign axi_awaddr  = dcache_axi_awaddr;
    assign axi_awvalid = dcache_axi_awvalid;
    assign dcache_axi_awready_int = axi_awready;
    assign axi_wdata   = dcache_axi_wdata;
    assign axi_wstrb   = dcache_axi_wstrb;
    assign axi_wvalid  = dcache_axi_wvalid;
    assign dcache_axi_wready_int = axi_wready;

    assign dcache_axi_bvalid = axi_bvalid;
    assign axi_bready = dcache_axi_bready;

    //===========================
    // CPU Core Stages
    //===========================

    if_stage i_if (
        .clk(clk),
        .rst_n(rst_n),

        // send fetch to icache
        .cache_req_valid(icache_req_valid),
        .cache_req_addr(icache_req_addr),

        // receive instruction
        .cache_rsp_valid(icache_rsp_valid),
        .cache_rsp_instr(icache_rsp_instr),

        .pc_out(if_pc),
        .instr_out(if_instr),
        .valid_out(if_valid)
    );

    id_stage i_id (
        .clk(clk),
        .rst_n(rst_n),
        .instr_in(if_instr),
        .pc_in(if_pc),
        .valid_in(if_valid),

        .rs1_out(id_rs1),
        .rs2_out(id_rs2),
        .imm_out(id_imm),
        .rd_out(id_rd),
        .pc_out(id_pc),

        .regwrite_out(id_regwrite),
        .memread_out(id_memread),
        .memwrite_out(id_memwrite),
        .branch_out(id_branch),
        .aluop_out(id_aluop)
    );

    ex_stage i_ex (
        .clk(clk),
        .rst_n(rst_n),
        .rs1_in(id_rs1),
        .rs2_in(id_rs2),
        .imm_in(id_imm),
        .rd_in(id_rd),
        .aluop_in(id_aluop),

        .regwrite_in(id_regwrite),
        .memread_in(id_memread),
        .memwrite_in(id_memwrite),

        .alu_res_out(ex_alu_res),
        .rs2_forward(ex_rs2_fwd),
        .rd_out(ex_rd),

        .regwrite_out(ex_regwrite),
        .memread_out(ex_memread),
        .memwrite_out(ex_memwrite)
    );

    mem_stage i_mem (
        .clk(clk),
        .rst_n(rst_n),

        // CPU request → d-cache
        .memread_in(ex_memread),
        .memwrite_in(ex_memwrite),
        .addr_in(ex_alu_res),
        .wdata_in(ex_rs2_fwd),

        .cache_req_valid(dcache_req_valid),
        .cache_req_addr(dcache_req_addr),
        .cache_req_wdata(dcache_req_wdata),
        .cache_req_wstrb(dcache_req_wstrb),
        .cache_req_we(dcache_req_we),

        // d-cache → CPU
        .cache_rsp_valid(dcache_rsp_valid),
        .cache_rsp_rdata(dcache_rsp_rdata),

        // OUT
        .rd_in(ex_rd),
        .regwrite_in(ex_regwrite),

        .data_out(mem_data_out),
        .alu_passthrough(mem_alu_res),
        .rd_out(mem_rd),
        .regwrite_out(mem_regwrite)
    );

    wb_stage i_wb (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(mem_data_out),
        .alu_in(mem_alu_res),
        .rd_in(mem_rd),
        .regwrite_in(mem_regwrite)
        // regfile write happens inside
    );

endmodule
