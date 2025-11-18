SYSTEM ARCHITECTURE SPECIFICATION
Project: AXI-Based Pipelined CPU + Multi-Level Cache Hierarchy

1. OVERVIEW

This design is a lightweight, educational yet realistic SoC-style architecture consisting of:

A 5-stage pipelined CPU core

Split L1 I-cache and D-cache (simple request/response interface)

Unified L2 cache with AXI4-Lite downstream master

Unified L3 cache with AXI4-Lite downstream master

Simple AXI RAM model (AXI4-Lite slave, single-beat)

The memory subsystem supports write-back, write-allocate caching at all levels, and approximates real CPU/GPU validation-style designs (AXI interfaces, hierarchical caches, miss/evict FSM structure).

2. CPU CORE SPECIFICATION
2.1 Pipeline Structure

The CPU implements a classic 5-stage RISC pipeline:

IF – Instruction Fetch

ID – Instruction Decode & Register Read

EX – ALU execution, branch evaluation

MEM – Data cache request/response

WB – Register write-back

Pipeline Features

Hazard detection unit

Stalls on load-to-use

Stalls when D-cache is busy

Forwarding unit

EX/MEM → EX

MEM/WB → EX

Branch resolution in EX stage

One-cycle penalty on taken branches

No speculation in current build

Single outstanding memory operation (stall on cache miss)

ALU

Supports ADD, SUB, AND, OR, XOR, SLT, shifts

Branch comparators implemented in EX stage

3. L1 CACHE SPECIFICATION
3.1 General

There are two L1 caches:

L1I – Instruction cache

L1D – Data cache

Both share the same interface and functional structure.

Size & Organization

Parameterizable, typical configuration:

128–256 sets

4-way or 8-way associativity

1-word cache lines (current build)

Write-back, write-allocate

Least-recently-used replacement via per-set age counters (pseudo-LRU)

3.2 L1 Interface (Simple Upstream Interface)

Each L1 presents a simple blocking interface to the CPU:

Request Channel

req_valid

req_addr[31:0]

req_we

req_wdata[31:0]

Response Channel

rsp_valid

rsp_rdata[31:0]

rsp_ready

On a miss, the L1:

Stalls the CPU

Sends its request down to L2 via the L1 arbiter

Waits for L2 response

Fills line, restarts pipeline

3.3 Miss Handling

Miss detected by tag mismatch in all ways

Victim selected by pseudo-LRU

If dirty victim → write-back to L2

Issue allocate request to L2

Complete read or write after line fill

Single outstanding miss supported

3.4 Arbitration

L1I and L1D do not directly connect to L2.
A small two-port → one-port L1 cache arbiter selects which L1 issues a request to L2.

4. L2 CACHE AXI SPECIFICATION
4.1 Overview

Unified L2 cache with downstream AXI4-Lite master used to access L3.

Organization

Parameterizable:

Default: 1024 sets, 8-way associative

Write-back, write-allocate

Single-beat lines (upgrade path to multi-beat)

Shared by both L1I + L1D through the L1 arbiter

Fully blocking: only one outstanding miss at a time

Pseudo-LRU via per-way counters

4.2 Upstream Interface

Matches the L1 simple interface:

s_req_valid, s_req_addr, s_req_we, s_req_wdata

s_rsp_valid, s_rsp_rdata, s_rsp_ready

4.3 AXI4-Lite Master (Downstream)

Used for L3 access. Signals:

Read Address

m_araddr

m_arvalid / m_arready

Read Data

m_rvalid / m_rready

m_rdata

Write Address

m_awaddr

m_awvalid / m_awready

Write Data

m_wdata, m_wstrb, m_wvalid, m_wready

Write Response

m_bvalid / m_bready

4.4 Miss Path

On miss:

Select victim (invalid-first, else LRU)

If dirty → write-back over AXI (AW/W/B)

Issue AXI read (AR/R)

Fill line

Complete the CPU request (read or write)

5. L3 CACHE AXI SPECIFICATION
5.1 Overview

Unified L3, almost identical to L2 but sits above it, accessing physical memory through AXI RAM.

Organization

Parameterizable:

Typical: 2048–4096 sets, 8–16 ways

1-word lines

AXI4-Lite slave upstream (L2 is the master)

AXI4-Lite master downstream (RAM is the slave)

Miss Path

Same behavior as L2:

Dirty → write-back to RAM

Allocate → AXI read from RAM

6. AXI RAM MODEL (TOP-LEVEL MEMORY)
6.1 Purpose

This is the final memory in the chain, acting as a simple AXI RAM:

Implements AXI4-Lite Slave interface

Accepts single-beat reads/writes

Has no bursts, no outstanding ID support

Internal byte-addressable RAM array

6.2 Behavior

Write: latch AW + W, update memory, return BVALID

Read: latch AR, return RVALID with stored memory data

No latency modeling unless added manually

7. MEMORY HIERARCHY SUMMARY
CPU
 │
 │  (Simple request/response interface)
 ▼
L1I Cache ——┐
            │
L1D Cache ——┘
        (Arbiter)
             │
             ▼
        L2 Cache (AXI Master)
             │
  AXI4-Lite (AR/AW/W/R/B)
             ▼
        L3 Cache (AXI Master/Slave)
             │
  AXI4-Lite (AR/AW/W/R/B)
             ▼
        AXI RAM (Slave)

8. CURRENT LIMITATIONS

Single-beat cache lines (upgrade path: multi-word + burst AXI)

Fully blocking caches (no MSHRs or multiple outstanding requests)

No store buffer

No instruction prefetch

No virtual memory / TLB

CPU pipeline has no speculative execution

AXI is AXI4-Lite, not full AXI4