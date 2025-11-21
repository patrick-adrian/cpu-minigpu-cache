Minimal 5-stage CPU core (educational).
Files:
- cpu_defs_pkg.sv : instruction encodings
- regfile.sv
- alu.sv
- if_stage.sv
- id_stage.sv
- ex_stage.sv
- mem_stage.sv
- wb_stage.sv
- cpu_top.sv : top-level CPU module exposing imem/dmem interfaces

Instruction format (simple):
[31:28] opcode, [27:24] rd, [23:20] rs1, [19:16] rs2, [15:0] imm16

Opcodes:
- 0x0 NOP
- 0x1 ADD  (rd = rs1 + rs2)
- 0x2 ADDI (rd = rs1 + imm16)
- 0x3 LOAD (rd = MEM[rs1 + imm16])
- 0x4 STORE(MEM[rs1 + imm16] = rs2)
- 0xF HALT

Note: This CPU is intentionally simple to be used in unit tests and UVM.
