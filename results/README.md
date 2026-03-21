# Benchmark Results

This directory contains performance benchmark results comparing scheduling
strategies on the Rust cosmos (aya-based) vs C cosmos (libbpf-based) vs
the kernel's built-in EEVDF scheduler.

## Structure

```
results/
  sweep-6.13/          # Native kernel 6.13.2 on 176-CPU AMD EPYC
    RESULTS.md         # Summary table with analysis
    eevdf/             # Raw schbench + stress-ng output (3 iterations)
    c-cosmos/          # Raw output with C cosmos attached
    rust-cosmos/       # Raw output with Rust cosmos attached
  sweep-6.16/          # Kernel 6.16.0 in virtme-ng VM (16 vCPUs)
    RESULTS.md         # Summary table
    eevdf/             # Raw output
    c-cosmos/          # Raw output
```

## Methodology

- Each benchmark runs 3 iterations; median is reported
- 5-second warmup after scheduler attachment
- 3-second settle between benchmarks
- Benchmarks: schbench (4 + 16 groups), stress-ng context/pipe/cpu
- Sequential mode execution to avoid interference

## How to reproduce

```bash
# Build both schedulers
(cd scx/scheds/rust/scx_cosmos && cargo build --release)
(cd scx/scheds/rust_only/scx_cosmos && cargo build --release)

# Run the sweep
bash testing/sweep-6.13.sh
```
