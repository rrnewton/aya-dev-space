# aya-rs.dev — Pure-Rust sched_ext Schedulers

This project adds **struct_ops BPF program support** to the [aya](https://github.com/aya-rs/aya)
Rust eBPF ecosystem, enabling pure-Rust Linux CPU schedulers via the
[sched_ext](https://lwn.net/Articles/922405/) framework.

## What's here

This is a development workspace that submodules two repos:

- **`aya/`** — fork of [aya-rs/aya](https://github.com/aya-rs/aya) with struct_ops,
  kfunc, kptr, and CO-RE postprocessor additions (branch `aya-scx.v2`)
- **`scx/`** — fork of [sched-ext/scx](https://github.com/sched-ext/scx) with pure-Rust
  schedulers and a shared eBPF library (branch `aya-next`)

Plus project-level tracking:

- **`.beads/`** — issue tracker ([minibeads](https://crates.io/crates/minibeads))
- **`docs/`** — architecture research and port mapping
- **`results/`** — benchmark data (EEVDF vs C cosmos vs Rust cosmos)
- **`testing/`** — VM test scripts and benchmark harness

## Schedulers

### scx_cosmos (production scheduler)

A complete port of the [C cosmos scheduler](https://github.com/sched-ext/scx/tree/main/scheds/rust/scx_cosmos)
to pure Rust. Features:

- Vtime-based deadline scheduling with dual-mode dispatch (round-robin / shared DSQ)
- Idle CPU scanning (preferred list, flat scan, `select_cpu_and`)
- NUMA-aware per-node DSQs
- SMT-aware idle core preference
- cpufreq scaling
- Deferred wakeup timer (batched IPIs)
- PMU perf event tracking via separate tracing program
- mm_affinity for cache-friendly wakeups

**Benchmark results** (kernel 6.13, 176-CPU AMD EPYC):

| Metric | EEVDF | C Cosmos | Rust Cosmos |
|--------|------:|----------:|------------:|
| schbench wakeup p99 (us) | 9 | 10 | **8** |
| schbench avg RPS | 724 | 674 | **729** |
| pipe throughput (ops/s) | 4.48M | 3.98M | **4.45M** |

### scx_simple (FIFO scheduler)

A minimal first-in-first-out scheduler demonstrating the pure-Rust BPF
scheduler pattern. ~100 lines of eBPF code.

## Key technical contributions

### 1. aya struct_ops support

Adds `BPF_PROG_TYPE_STRUCT_OPS` and `BPF_MAP_TYPE_STRUCT_OPS` to aya,
including BTF sanitization, kfunc call resolution, and struct_ops map
creation with kernel wrapper structs.

### 2. Kfunc call resolution

The Rust BPF compiler emits kfunc calls as `BPF_PSEUDO_CALL` with
relocations to undefined extern symbols. aya detects these, patches
`src_reg` to `BPF_PSEUDO_KFUNC_CALL`, and resolves the kfunc name
against vmlinux BTF at load time.

### 3. CO-RE post-processor

Since `rustc` cannot emit LLVM `preserve_access_index` annotations,
we built a post-processor that:
- Reads `.aya.core_relo` markers emitted by `core_read!`/`core_write!` macros
- Scans BPF instructions for matching field offsets
- Generates `.BTF.ext` CO-RE relocation records
- The aya loader then patches offsets at load time for the target kernel

### 4. Safe BPF abstractions

- **`BpfGlobal<T>`** — safe wrapper for `static mut` globals (81% unsafe reduction)
- **`bpf_map!`/`bpf_global!` macros** — hide `#[unsafe(link_section)]` boilerplate
- **Safe map `get_ref()`/`get_mut()`** — return Rust references from BPF map lookups
- **`core_read!`/`core_write!`** — safe macros for kernel struct field access

## Quick Start

```bash
# Install dependencies (Rust nightly, bpf-linker, clang)
make install-deps

# Build
make build

# Run on this host (30s, requires sudo + sched_ext kernel 6.12+)
make test

# Run in a VM (requires virtme-ng)
make test-vm

# Build a container image
make container
```

## Building

```bash
# Build the pure-Rust cosmos scheduler (scx_cosmos_rs)
make build
# or directly:
cd scx/scheds/rust_only/scx_cosmos && cargo build --release

# For kernel 6.16+:
make build-6.16

# Run (requires root + sched_ext kernel)
sudo ./scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos_rs
```

### Container build

```bash
podman build -t scx_cosmos_rs .
# The container holds the binary at /usr/local/bin/scx_cosmos_rs
# It needs to run with --privileged to attach BPF programs
```

## Status

- [x] aya struct_ops support (PR [#1495](https://github.com/aya-rs/aya/pull/1495))
- [x] scx_simple FIFO scheduler
- [x] scx_cosmos full port (28/28 C functions ported)
- [x] Port accuracy audit (13 bugs found and fixed)
- [x] CO-RE post-processor pipeline
- [x] Kernel 6.13 benchmarks (Rust cosmos matches/beats C cosmos)
- [ ] Kernel 6.16+ verification (CO-RE + kfunc setters)
- [ ] Safe BPF type system research (see `docs/safe-bpf-map-types.md`)

## Docs

- [`CLAUDE.md`](CLAUDE.md) — development workflow and conventions
- [`docs/cosmos-port-mapping.md`](docs/cosmos-port-mapping.md) — C→Rust function mapping
- [`docs/safe-bpf-map-types.md`](docs/safe-bpf-map-types.md) — research on safe BPF APIs
- [`docs/llvm_bpf_core_research.md`](docs/llvm_bpf_core_research.md) — LLVM CO-RE pass analysis
- [`results/sweep-6.13/RESULTS.md`](results/sweep-6.13/RESULTS.md) — benchmark data
