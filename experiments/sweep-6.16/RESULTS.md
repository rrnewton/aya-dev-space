# Benchmark Results: EEVDF vs C Cosmos
## Kernel 6.16.0, virtme-ng VM (50 vCPUs, 70G memory), 3 iterations each (median reported)

### System
- **CPU**: AMD EPYC host, VM with 50 vCPUs (no NUMA, SMT off in guest)
- **Kernel**: 6.16.0
- **Date**: 2026-03-21
- **VM**: virtme-ng with 9p shared filesystem, KVM acceleration

### schbench (wakeup latency + throughput)

| Benchmark | Metric | EEVDF | C Cosmos | C Cosmos vs EEVDF |
|-----------|--------|------:|----------:|------------------:|
| **4 groups** | Wakeup p99 (us) | 22 | 21 | -5% |
| | avg RPS | 717 | 722 | +0.7% |
| **16 groups** | Wakeup p99 (us) | 20 | 20 | 0% |
| | avg RPS | 2,869 | 2,875 | +0.2% |

### stress-ng (throughput)

| Benchmark | Metric | EEVDF | C Cosmos | C Cosmos vs EEVDF |
|-----------|--------|------:|----------:|------------------:|
| **context switch** | bogo ops/s | 13,276 | 13,211 | -0.5% |
| **pipe** | bogo ops/s | 1,463,509 | 1,461,837 | -0.1% |
| **cpu compute** | bogo ops/s | 11,580 | 11,603 | +0.2% |

### Notes

- C cosmos iteration 1 (schbench 4g) had warmup instability: RPS=631, p99=27us. Medians used.
- On kernel 6.16 in a VM, C cosmos and EEVDF perform nearly identically across all benchmarks.
- Context switch and pipe throughput are essentially tied (within noise margin).
- The VM environment (9p filesystem, no NUMA) differs from bare-metal; results are not directly comparable to sweep-6.13 bare-metal numbers.
- VM pipe throughput (~1.5M ops/s) is significantly lower than bare-metal (~4.5M ops/s) due to virtualization overhead.
- VM context switch throughput (~13K ops/s) is also lower than bare-metal (~19K ops/s).

### Comparison with kernel 6.13 bare-metal results

| Benchmark | Metric | 6.13 EEVDF (bare) | 6.16 EEVDF (VM) | 6.13 C Cosmos (bare) | 6.16 C Cosmos (VM) |
|-----------|--------|-------------------:|----------------:|---------------------:|-------------------:|
| schbench 4g | p99 wakeup (us) | 9 | 22 | 10 | 21 |
| schbench 4g | avg RPS | 724 | 717 | 674 | 722 |
| schbench 16g | p99 wakeup (us) | 11 | 20 | 9 | 20 |
| schbench 16g | avg RPS | 2,862 | 2,869 | 2,867 | 2,875 |
| context | ops/s | 18,942 | 13,276 | 18,011 | 13,211 |
| pipe | ops/s | 4,477,460 | 1,463,509 | 3,976,731 | 1,461,837 |
| cpu | ops/s | 11,670 | 11,580 | 11,514 | 11,603 |

### Raw data location
`/home/newton/working_copies/aya-rs.dev/results/sweep-6.16/`
- `eevdf/` -- EEVDF raw results
- `c-cosmos/` -- C cosmos raw results
