# Experiment Results

Performance benchmarks comparing scheduling strategies: Rust cosmos (aya-based)
vs C cosmos (libbpf-based) vs kernel EEVDF.

## Provenance requirements

Every experiment directory must include:
- `meta.txt` or similar metadata describing kernel version, hardware, date
- Raw data files (CSV/txt) — version-controlled
- A `RESULTS.md` summary with methodology notes

Do NOT commit binary artifacts or large log files here. Add them to
`.gitignore` if generated.

## Structure

```
experiments/
  sweep-6.13/          # Native kernel 6.13.2 on 176-CPU AMD EPYC
  sweep-6.16/          # Kernel 6.16.0 in virtme-ng VM (16 vCPUs)
  native-6.13/         # Native kernel benchmarks (untracked data)
  purerust-cosmos/     # Pure-Rust cosmos benchmarks
  stress-test/         # Stress test results
```

## Methodology

- Each benchmark runs 3 iterations; median is reported
- 5-second warmup after scheduler attachment
- 3-second settle between benchmarks
- Benchmarks: schbench (4 + 16 groups), stress-ng context/pipe/cpu
- Sequential mode execution to avoid interference

## How to reproduce

```bash
(cd scx/scheds/rust/scx_cosmos && cargo build --release)
(cd scx/scheds/rust_only/scx_cosmos && cargo build --release)
bash testing/sweep-6.13.sh
```
