//===========================================================
// l2_cache.sv - Unified L2 Cache
//===========================================================

module l2_cache #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter NUM_SETS = 256,
    parameter ASSOC = 8,
    parameter LINE_WORDS = 4  // words per line
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // L1 interface
    input  logic                    l1_req_valid,
    input  logic [ADDR_WIDTH-1:0]   l1_req_addr,
    input  logic                    l1_req_we,
    input  logic [DATA_WIDTH-1:0]   l1_req_wdata,
    output logic [DATA_WIDTH-1:0]   l1_rsp_rdata,
    output logic                    l1_rsp_valid,

    // AXI downstream interface (L3 or RAM)
    output logic [ADDR_WIDTH-1:0]   axi_araddr,
    output logic                    axi_arvalid,
    input  logic                    axi_arready,
    input  logic [DATA_WIDTH-1:0]   axi_rdata,
    input  logic                    axi_rvalid,
    output logic                    axi_rready,

    output logic [ADDR_WIDTH-1:0]   axi_awaddr,
    output logic                    axi_awvalid,
    input  logic                    axi_awready,
    output logic [DATA_WIDTH-1:0]   axi_wdata,
    output logic [3:0]              axi_wstrb,
    output logic                    axi_wvalid,
    input  logic                    axi_wready,
    input  logic                    axi_bvalid,
    output logic                    axi_bready
);

    //===========================================================
    // Type and address split
    //===========================================================

    typedef struct packed {
        logic valid;
        logic dirty;
        logic [ADDR_WIDTH-1-($clog2(NUM_SETS*LINE_WORDS))-1:0] tag;
        logic [DATA_WIDTH-1:0] data[LINE_WORDS];
    } line_t;

    line_t cache_mem[0:NUM_SETS-1][0:ASSOC-1];
    logic [$clog2(ASSOC)-1:0] lru_age[0:NUM_SETS-1][0:ASSOC-1];

    localparam SET_BITS    = $clog2(NUM_SETS);
    localparam OFFSET_BITS = $clog2(LINE_WORDS);
    localparam TAG_BITS    = ADDR_WIDTH - SET_BITS - OFFSET_BITS;

    wire [SET_BITS-1:0]  set   = l1_req_addr[OFFSET_BITS +: SET_BITS];
    wire [OFFSET_BITS-1:0] off = l1_req_addr[0 +: OFFSET_BITS];
    wire [TAG_BITS-1:0]   tag   = l1_req_addr[ADDR_WIDTH-1 -: TAG_BITS];

    // Hit detection
    logic hit;
    logic [$clog2(ASSOC)-1:0] hit_way;

    always_comb begin
        hit = 0;
        hit_way = '0;
        for (int i=0; i<ASSOC; i++) begin
            if (cache_mem[set][i].valid && cache_mem[set][i].tag == tag) begin
                hit = 1;
                hit_way = i;
            end
        end
    end

    //===========================================================
    // AXI state machine (simplified)
    //===========================================================

    typedef enum logic [1:0] {IDLE, READ, WRITEBACK} axi_state_t;
    axi_state_t state;

    logic [$clog2(ASSOC)-1:0] replace_way;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l1_rsp_valid <= 0;
            state <= IDLE;
            axi_arvalid <= 0;
            axi_awvalid <= 0;
            axi_wvalid  <= 0;
            axi_rready  <= 0;
            axi_bready  <= 0;
            // invalidate all lines
            for (int s=0; s<NUM_SETS; s++) begin
                for (int w=0; w<ASSOC; w++) begin
                    cache_mem[s][w].valid <= 0;
                    cache_mem[s][w].dirty <= 0;
                end
            end
        end else begin
            l1_rsp_valid <= 0;

            case (state)
                IDLE: begin
                    if (l1_req_valid) begin
                        if (hit) begin
                            // L2 hit: return data
                            l1_rsp_rdata <= cache_mem[set][hit_way].data[off];
                            l1_rsp_valid <= 1;

                            if (l1_req_we) begin
                                cache_mem[set][hit_way].data[off] <= l1_req_wdata;
                                cache_mem[set][hit_way].dirty <= 1;
                            end
                        end else begin
                            // L2 miss: choose replacement way (simple: oldest)
                            replace_way <= 0;
                            for (int i=0; i<ASSOC; i++) begin
                                if (!cache_mem[set][i].valid) begin
                                    replace_way <= i;
                                end
                            end
                            // If dirty, first writeback
                            if (cache_mem[set][replace_way].valid && cache_mem[set][replace_way].dirty) begin
                                state <= WRITEBACK;
                                axi_awaddr <= {cache_mem[set][replace_way].tag, set, '0};
                                axi_awvalid <= 1;
                                axi_wdata  <= cache_mem[set][replace_way].data[0]; // only first word for simplicity
                                axi_wstrb  <= 4'hF;
                                axi_wvalid <= 1;
                                axi_bready <= 1;
                            end else begin
                                state <= READ;
                                axi_araddr  <= l1_req_addr & ~((1<<OFFSET_BITS)-1);
                                axi_arvalid <= 1;
                                axi_rready  <= 1;
                            end
                        end
                    end
                end

                WRITEBACK: begin
                    if (axi_awready && axi_wready) begin
                        axi_awvalid <= 0;
                        axi_wvalid  <= 0;
                    end
                    if (axi_bvalid) begin
                        axi_bready <= 0;
                        state <= READ;
                        axi_araddr  <= l1_req_addr & ~((1<<OFFSET_BITS)-1);
                        axi_arvalid <= 1;
                        axi_rready  <= 1;
                    end
                end

                READ: begin
                    if (axi_rvalid) begin
                        cache_mem[set][replace_way].data[0] <= axi_rdata; // simplified: only 1 word
                        cache_mem[set][replace_way].valid <= 1;
                        cache_mem[set][replace_way].dirty <= l1_req_we ? 1 : 0;

                        l1_rsp_rdata <= axi_rdata;
                        l1_rsp_valid <= 1;

                        axi_arvalid <= 0;
                        axi_rready  <= 0;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
