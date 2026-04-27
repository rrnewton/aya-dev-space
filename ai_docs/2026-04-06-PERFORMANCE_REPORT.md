# MITOSIS Scheduler Performance Report

## Test Environment

| Parameter | Value |
|-----------|-------|
| VM Kernel | 6.13.2-fbk7 |
| VM CPUs | 8-16 (QEMU KVM, 2 sockets, 4 cores, 2 threads) |
| VM Memory | 2 GB |
| NUMA | 2 nodes (1G each) |
| Host | 176-core x86_64, 6.9.0-fbk13 |

## Scheduler Verification Results

All three pure-Rust BPF schedulers verified on kernel 6.13:

| Scheduler | Loads | Runs 10s | Kernel 6.13 | Kernel 6.16 | Kernel 6.17 |
|-----------|-------|----------|-------------|-------------|-------------|
| CFS (default) | N/A | N/A | baseline | baseline | baseline |
| scx_simple | Yes | Yes | **PASS** | FAIL* | FAIL* |
| scx_cosmos | Yes | Yes | **PASS** | FAIL** | FAIL** |
| scx_mitosis (default) | Yes | Yes | **PASS** | FAIL*** | FAIL*** |
| scx_mitosis --llc-aware | Yes | Yes | **PASS** | - | - |
| scx_mitosis --llc+steal | Yes | Yes | **PASS** | - | - |

\* struct_ops map layout mismatch (6.16 added new sched_ext_ops fields)
\** core_write! to trusted_ptr rejected (needs scx_bpf_task_set_* kfuncs)
\*** CO-RE relocation corruption (FIXED in aya commit `4c86ba5a`)

## CO-RE Fix Impact

The CO-RE relocation fix (zeroing stale `.rel.BTF.ext` sections) is a
**landmark fix for the aya ecosystem**. Before the fix, ALL pure-Rust
schedulers failed on kernel 6.16+ with:

```
relocation #1 of kind `Int(...)` not valid for type `Int`:
field relocation on a type that doesn't have fields
```

After the fix, scx_cosmos on 6.16 progresses past CO-RE relocation to
the BPF verifier stage, where it fails on a separate `core_write!`
permission issue (needs `kernel_6_16` feature flag for kfunc setters).

## Architecture Comparison

| Feature | scx_simple | scx_cosmos | scx_mitosis |
|---------|-----------|------------|-------------|
| Scheduling policy | FIFO | Deadline + vruntime | Cell-based vruntime |
| DSQ topology | Global | Per-NUMA node | Per-cell x LLC |
| Idle CPU selection | select_cpu_dfl | SMT-aware pick_idle | select_cpu_dfl (stub) |
| Vtime charging | None | weight + deadline | weight-proportional |
| Cgroup awareness | None | None | Yes (init/exit/move) |
| LLC awareness | None | None | Yes (when enabled) |
| Work stealing | No | No | Yes (LLC-to-LLC) |
| Cpufreq integration | No | Yes (PMU-based) | No |
| struct_ops callbacks | 5 | 12 | 14 + 3 aux progs |
| Lines of Rust BPF | ~100 | ~2000 | ~2100 |
| Lines of userspace | ~120 | ~600 | ~600 |
| PORT_TODOs remaining | 0 | 0 | 5 |

## Performance Testing

### Available tools
- `testing/benchmark-compare.sh` — Full comparison with stress-ng (CPU, pipe, fork)
- `testing/quick-bench.sh` — Quick comparison with matrixprod workload

### How to run on bare metal (6.12+ host)

```bash
# Build all schedulers
cd scx/scheds/rust_only/scx_simple && cargo build --release
cd ../scx_cosmos && cargo build --release
cd ../scx_mitosis && cargo build --release

# CFS baseline
stress-ng --cpu $(nproc) --cpu-method matrixprod --timeout 30s --metrics-brief

# scx_simple
sudo ./scx_simple &
stress-ng --cpu $(nproc) --cpu-method matrixprod --timeout 30s --metrics-brief
sudo kill %1; sleep 2

# scx_cosmos
sudo ./scx_cosmos_rs &
stress-ng --cpu $(nproc) --cpu-method matrixprod --timeout 30s --metrics-brief
sudo kill %1; sleep 2

# scx_mitosis (default)
sudo ./scx_mitosis_rs &
stress-ng --cpu $(nproc) --cpu-method matrixprod --timeout 30s --metrics-brief
sudo kill %1; sleep 2

# scx_mitosis (LLC-aware + work stealing)
sudo ./scx_mitosis_rs --enable-llc-awareness --enable-work-stealing &
stress-ng --cpu $(nproc) --cpu-method matrixprod --timeout 30s --metrics-brief
sudo kill %1
```

### VM testing note

virtme-ng's `--script-sh` mode does not forward guest stdout to the host,
so throughput numbers cannot be captured programmatically in VM tests.
The pass/fail verification above confirms all schedulers load, handle
real workloads (stress-ng, system daemons), and exit cleanly.

## Current MITOSIS Status

### What works
- Full scheduler lifecycle (init → attach → run → detach → exit)
- 14 struct_ops callbacks + 3 auxiliary BPF programs
- Vtime-ordered scheduling with weight-proportional charging
- Cell + LLC DSQ topology with per-cell dispatch
- LLC-aware mode with weighted random assignment
- Work stealing across LLC domains
- Cgroup lifecycle tracking (init/exit/move)
- Debug event circular buffer
- Userspace stats collection infrastructure

### What needs aya infrastructure (5 PORT_TODOs)
- **kptr support (11)** — cell cpumask kptrs for per-cell CPU affinity
- **update_task_cpumask (4)** — intersect cell mask with task affinity
- **bpf_for_each CSS (3)** — cgroup hierarchy iteration
- **CO-RE cpuset (2)** — cpuset.cpus introspection
- **task_cgroup (2)** — read task's cgroup via p->cgroups->dfl_cgrp
- **kptr globals (2)** — all_cpumask and root_cgrp kptr storage

## Date

Generated: 2026-04-07
