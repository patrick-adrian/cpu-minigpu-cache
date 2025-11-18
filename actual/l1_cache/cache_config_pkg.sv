package cache_config_pkg;
  // Common parameters for L1 caches
  parameter int ADDR_WIDTH = 32;
  parameter int DATA_WIDTH = 32;
  parameter int LINE_WORDS = 1; // words per line (keep 1 for simplicity)
  parameter int NUM_SETS = 64;
  parameter int ASSOC = 4; // 4-way
endpackage : cache_config_pkg
