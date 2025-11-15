package cpu_defs_pkg;
  // Simple instruction set encoding
  // 32-bit instruction: [31:28]=opcode, [27:24]=rd, [23:20]=rs1, [19:16]=rs2/immed4, [15:0]=imm16 (for immed)
  typedef logic [31:0] instr_t;
  typedef logic [31:0] data_t;
  typedef logic [31:0] addr_t;

  // Opcodes (4-bit)
  localparam logic [3:0] OP_NOP   = 4'h0;
  localparam logic [3:0] OP_ADD   = 4'h1; // rd = rs1 + rs2
  localparam logic [3:0] OP_ADDI  = 4'h2; // rd = rs1 + imm16
  localparam logic [3:0] OP_LOAD  = 4'h3; // rd = MEM[rs1 + imm16]
  localparam logic [3:0] OP_STORE = 4'h4; // MEM[rs1 + imm16] = rs2
  localparam logic [3:0] OP_HALT  = 4'hF; // stop

endpackage : cpu_defs_pkg
