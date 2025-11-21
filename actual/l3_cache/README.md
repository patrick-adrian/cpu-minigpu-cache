L3 Cache (simplified unified L3)
- l3_cache.sv : unified L3 cache with a simplified AXI-like slave upstream and a simple downstream mem interface.
Notes:
- Single-word cache lines (LINE_WORDS=1) for clarity & simulation speed.
- Upstream interface behaves like a simplified AXI slave: s_ar*, s_r*, s_aw*, s_w*, s_b* signals (single-beat).
- Downstream is a simple mem_* handshake (mem_addr, mem_rd, mem_wr, mem_wdata, mem_rdata, mem_ready).
- Replacement: prefer invalid lines; otherwise pick way 0 (can be improved).
- Write-back and write-allocate implemented in a basic form.
- Good for integration and simulation; extend for burst transfers and full AXI compliance.
