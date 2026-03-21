#!/bin/bash
# Full benchmark sweep: EEVDF vs C cosmos vs Rust cosmos on kernel 6.13
# Each mode runs 3 iterations of each benchmark, taking median

set -euo pipefail

RESULTS=/home/newton/working_copies/aya-rs.dev/results/sweep-6.13
RUST_COSMOS=/home/newton/working_copies/aya-rs.dev/scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos
C_COSMOS=/home/newton/working_copies/aya-rs.dev/scx/target/release/scx_cosmos
ITERS=${BENCH_ITERATIONS:-3}
WARMUP=5
SETTLE=3
NCPUS=$(nproc)
HALF_CPUS=$((NCPUS / 2))
WORKERS=$((HALF_CPUS > 88 ? 88 : HALF_CPUS))

echo "=== Benchmark Sweep ==="
echo "Kernel: $(uname -r)"
echo "CPUs: $NCPUS"
echo "Workers: $WORKERS (for CPU-bound tests)"
echo "Iterations: $ITERS"
echo "Results: $RESULTS"
echo ""

run_benchmarks() {
    local mode=$1
    local dir=$RESULTS/$mode
    mkdir -p "$dir"

    echo "=== [$mode] Starting benchmarks ==="
    date >> "$dir/meta.txt"
    uname -r >> "$dir/meta.txt"

    for iter in $(seq 1 $ITERS); do
        echo "--- [$mode] Iteration $iter/$ITERS ---"

        # schbench 4 groups
        echo "  schbench 4 groups..."
        schbench -m 4 -t 1 -r 10 2>&1 | tee "$dir/schbench-4g-iter$iter.txt"
        sleep $SETTLE

        # schbench 16 groups
        echo "  schbench 16 groups..."
        schbench -m 16 -t 1 -r 10 2>&1 | tee "$dir/schbench-16g-iter$iter.txt"
        sleep $SETTLE

        # stress-ng context switch
        echo "  context switch..."
        stress-ng --context 4 --timeout 10 --metrics 2>&1 | tee "$dir/context-iter$iter.txt"
        sleep $SETTLE

        # stress-ng pipe
        echo "  pipe..."
        stress-ng --pipe 4 --timeout 10 --metrics 2>&1 | tee "$dir/pipe-iter$iter.txt"
        sleep $SETTLE

        # stress-ng cpu
        echo "  cpu compute..."
        stress-ng --cpu 8 --timeout 10 --metrics 2>&1 | tee "$dir/cpu-iter$iter.txt"
        sleep $SETTLE
    done

    echo "=== [$mode] Done ==="
}

# ── Mode 1: EEVDF (no scheduler) ──
echo ""
echo "============================================"
echo "  MODE 1: EEVDF (built-in scheduler)"
echo "============================================"
sleep $WARMUP
run_benchmarks eevdf

# ── Mode 2: C cosmos ──
echo ""
echo "============================================"
echo "  MODE 2: C cosmos (libbpf-rs)"
echo "============================================"
sudo $C_COSMOS &
SCHED_PID=$!
sleep $WARMUP
echo "C cosmos running (PID $SCHED_PID)"
run_benchmarks c-cosmos
sudo kill $SCHED_PID 2>/dev/null || true
wait $SCHED_PID 2>/dev/null || true
echo "C cosmos stopped"
sleep $SETTLE

# ── Mode 3: Rust cosmos (aya) ──
echo ""
echo "============================================"
echo "  MODE 3: Rust cosmos (aya)"
echo "============================================"
sudo $RUST_COSMOS &
SCHED_PID=$!
sleep $WARMUP
echo "Rust cosmos running (PID $SCHED_PID)"
run_benchmarks rust-cosmos
sudo kill $SCHED_PID 2>/dev/null || true
wait $SCHED_PID 2>/dev/null || true
echo "Rust cosmos stopped"

echo ""
echo "============================================"
echo "  SWEEP COMPLETE"
echo "  Results in: $RESULTS"
echo "============================================"
