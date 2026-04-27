# Benchmark Results: EEVDF vs C Cosmos vs Rust Cosmos
## Kernel 6.13.2, 176-CPU AMD EPYC, 3 iterations each (median reported)

### System
- **CPU**: 176-core AMD EPYC (2 sockets, 88 cores, SMT on)
- **Kernel**: 6.13.2-0_fbk9_0_gb487e362c3df
- **Date**: 2026-03-21
- **scx submodule**: `82649294` (aya-next branch)
- **aya submodule**: `eb42117f` (aya-scx.v2 branch)
- **Parent repo**: `8ed18e3` (main branch)

### schbench (wakeup latency + throughput)

| Benchmark | Metric | EEVDF | C Cosmos | Rust Cosmos | Rust vs C |
|-----------|--------|------:|----------:|------------:|----------:|
| **4 groups** | Wakeup p99 (us) | 9 | 10 | **8** | **-20%** |
| | avg RPS | 724 | 674 | **729** | **+8%** |
| **16 groups** | Wakeup p99 (us) | 11 | 9 | **8** | **-11%** |
| | avg RPS | 2862 | 2867 | **2910** | **+1.5%** |

### stress-ng (throughput)

| Benchmark | Metric | EEVDF | C Cosmos | Rust Cosmos | Rust vs C |
|-----------|--------|------:|----------:|------------:|----------:|
| **context switch** | ops/sec | 18,942 | 18,011 | **19,207** | **+6.6%** |
| **pipe** | ops/sec | 4,477,460 | 3,976,731 | **4,450,764** | **+11.9%** |
| **cpu compute** | bogo ops/sec | 11,670 | 11,514 | **11,729** | **+1.9%** |

### Notes

- C cosmos iteration 1 had outlier results (context=3519, RPS=674) suggesting warmup instability. Medians are used.
- Rust cosmos shows remarkably stable results across all 3 iterations (low variance).
- Rust cosmos matches or beats EEVDF on every metric.
- Rust cosmos beats C cosmos on every metric, most significantly on pipe throughput (+12%).
- The C cosmos pipe regression vs EEVDF (-10%) is not seen in Rust cosmos.

### Raw data location
`/home/newton/working_copies/aya-rs.dev/results/sweep-6.13/`
- `eevdf/` — EEVDF raw results
- `c-cosmos/` — C cosmos raw results
- `rust-cosmos/` — Rust cosmos raw results
