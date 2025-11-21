Mini-GPU (minimal prototype) - rtl/mini_gpu/

Files:
- mini_gpu_top.sv       : Top-level GPU connecting warp scheduler, vector ALU, vregfile, and AXI bridge.
- warp_scheduler.sv     : Very small scheduler that issues sequential memory work items.
- vector_alu.sv         : Minimal SIMD ALU that consumes mem responses and writes to vregs.
- vregfile.sv           : Simple banked vector register file.
- axi_master_bridge.sv  : Lightweight AXI4-lite single-beat master bridge used by GPU for memory ops.

How it works:
- The host pulses `start` with `kernel_id` and `work_items`.
- `warp_scheduler` issues memory read requests (addresses) for each work item.
- `axi_master_bridge` turns those requests into AXI transactions toward L2/L3.
- `vector_alu` converts returned data into vector register writes.
- This is a minimal, extendable prototype: add bursts, multiple outstanding requests,
  L1 GPU cache, per-lane lane-specific logic, complex kernels, thread management, etc.

Integration:
- Connect `m_*` AXI master ports to your SoC AXI interconnect (L2).
- Hook the `start` signal from CPU command/CSR interface.
- Expand `warp_scheduler` to read a work descriptor table in memory.
