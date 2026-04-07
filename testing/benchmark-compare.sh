#!/bin/bash
#
# benchmark-compare.sh — Compare scheduler performance
#
# Runs each scheduler with stress-ng workloads and produces a comparison.
# Designed to run inside a virtme-ng VM via run-in-vm.sh.
#
# Usage:
#   ./testing/benchmark-compare.sh [duration_per_scheduler]
#
# Default: 30s per scheduler run, 20s workload within each.

set -euo pipefail

DURATION="${1:-30}"
WORKLOAD_DURATION=$((DURATION - 10))
if [ "$WORKLOAD_DURATION" -lt 5 ]; then
    WORKLOAD_DURATION=5
fi

RESULTS_DIR="/tmp/sched-bench-$$"
mkdir -p "$RESULTS_DIR"

NCPUS=$(nproc)
# Use half the CPUs for workloads so the scheduler has room to breathe
WORK_CPUS=$(( NCPUS / 2 ))
if [ "$WORK_CPUS" -lt 2 ]; then WORK_CPUS=2; fi

echo "================================================================"
echo "  Scheduler Performance Comparison"
echo "================================================================"
echo "  Date:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  Kernel:   $(uname -r)"
echo "  CPUs:     $NCPUS"
echo "  Work CPUs: $WORK_CPUS"
echo "  Duration: ${DURATION}s per scheduler (${WORKLOAD_DURATION}s workload)"
echo "================================================================"
echo ""

# ── Workload function ────────────────────────────────────────────────

run_workloads() {
    local tag="$1"
    local outdir="$RESULTS_DIR/$tag"
    mkdir -p "$outdir"

    echo "  [workload] stress-ng --cpu $WORK_CPUS --timeout ${WORKLOAD_DURATION}s ..."

    # CPU-bound workload: matrix multiplication, prime sieve
    stress-ng --cpu "$WORK_CPUS" \
              --cpu-method matrixprod \
              --timeout "${WORKLOAD_DURATION}s" \
              --metrics-brief \
              2>"$outdir/stress-cpu.txt" &
    local cpu_pid=$!

    # Context-switch workload: pipe ping-pong
    stress-ng --pipe "$WORK_CPUS" \
              --timeout "${WORKLOAD_DURATION}s" \
              --metrics-brief \
              2>"$outdir/stress-pipe.txt" &
    local pipe_pid=$!

    # Fork workload: rapid process creation
    stress-ng --fork 2 \
              --timeout "${WORKLOAD_DURATION}s" \
              --metrics-brief \
              2>"$outdir/stress-fork.txt" &
    local fork_pid=$!

    wait $cpu_pid $pipe_pid $fork_pid 2>/dev/null || true
}

# ── Extract metrics ──────────────────────────────────────────────────

extract_bogo_ops() {
    local file="$1"
    if [ -f "$file" ]; then
        grep "bogo ops/s" "$file" 2>/dev/null | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+$/ || $i ~ /^[0-9]+$/) {print $i; exit}}' || echo "N/A"
    else
        echo "N/A"
    fi
}

extract_ops_per_sec() {
    local file="$1"
    local stressor="$2"
    if [ -f "$file" ]; then
        grep "$stressor" "$file" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+$/) {print $i; exit}}' || echo "N/A"
    else
        echo "N/A"
    fi
}

# ── Run a single scheduler benchmark ─────────────────────────────────

run_benchmark() {
    local sched_name="$1"
    local sched_bin="$2"
    shift 2
    local sched_args=("$@")
    local tag=$(echo "$sched_name" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')

    echo ""
    echo "── $sched_name ──────────────────────────────────────"

    # Start scheduler in background
    echo "  [sched] Starting: $sched_bin ${sched_args[*]:-}"
    $sched_bin "${sched_args[@]}" >"$RESULTS_DIR/$tag/sched.log" 2>&1 &
    local sched_pid=$!

    # Wait for scheduler to attach
    sleep 2

    # Check if scheduler attached
    local sched_state=""
    if [ -f /sys/kernel/sched_ext/root/ops ]; then
        sched_state=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none")
    fi

    if [ "$sched_state" = "none" ] || [ -z "$sched_state" ]; then
        echo "  [WARN] Scheduler did not attach (state: $sched_state)"
        echo "  [WARN] Output:"
        head -5 "$RESULTS_DIR/$tag/sched.log" 2>/dev/null || true
        kill $sched_pid 2>/dev/null || true
        wait $sched_pid 2>/dev/null || true

        # Record failure
        echo "FAILED" > "$RESULTS_DIR/$tag/status"
        return
    fi

    echo "  [sched] Attached: $sched_state"
    echo "ATTACHED" > "$RESULTS_DIR/$tag/status"

    # Run workloads
    run_workloads "$tag"

    # Stop scheduler
    echo "  [sched] Stopping..."
    kill $sched_pid 2>/dev/null || true
    wait $sched_pid 2>/dev/null || true
    sleep 1

    echo "  [done] $sched_name complete"
}

# ── Baseline: no ext scheduler (CFS) ────────────────────────────────

echo ""
echo "── CFS Baseline (no ext scheduler) ──────────────────────"
mkdir -p "$RESULTS_DIR/cfs_baseline"
echo "ATTACHED" > "$RESULTS_DIR/cfs_baseline/status"
run_workloads "cfs_baseline"
echo "  [done] CFS baseline complete"

# ── Run each scheduler ───────────────────────────────────────────────

# Find scheduler binaries
SIMPLE_BIN=$(find /home -name "scx_simple" -path "*/release/*" -type f 2>/dev/null | head -1)
COSMOS_BIN=$(find /home -name "scx_cosmos_rs" -path "*/release/*" -type f 2>/dev/null | head -1)
MITOSIS_BIN=$(find /home -name "scx_mitosis_rs" -path "*/release/*" -type f 2>/dev/null | head -1)

if [ -n "$SIMPLE_BIN" ]; then
    run_benchmark "scx_simple" "$SIMPLE_BIN"
fi

if [ -n "$COSMOS_BIN" ]; then
    run_benchmark "scx_cosmos" "$COSMOS_BIN"
fi

if [ -n "$MITOSIS_BIN" ]; then
    run_benchmark "MITOSIS (default)" "$MITOSIS_BIN"
    run_benchmark "MITOSIS (LLC-aware)" "$MITOSIS_BIN" --enable-llc-awareness
    run_benchmark "MITOSIS (LLC+steal)" "$MITOSIS_BIN" --enable-llc-awareness --enable-work-stealing
fi

# ── Results table ────────────────────────────────────────────────────

echo ""
echo ""
echo "================================================================"
echo "  RESULTS"
echo "================================================================"
echo ""

printf "%-25s %8s %12s %12s %12s\n" \
    "Scheduler" "Status" "CPU ops/s" "Pipe ops/s" "Fork ops/s"
printf "%-25s %8s %12s %12s %12s\n" \
    "-------------------------" "--------" "------------" "------------" "------------"

for tag_dir in "$RESULTS_DIR"/*/; do
    tag=$(basename "$tag_dir")
    status=$(cat "$tag_dir/status" 2>/dev/null || echo "UNKNOWN")

    if [ "$status" != "ATTACHED" ]; then
        printf "%-25s %8s %12s %12s %12s\n" "$tag" "FAIL" "-" "-" "-"
        continue
    fi

    cpu_ops=$(extract_ops_per_sec "$tag_dir/stress-cpu.txt" "matrixprod")
    pipe_ops=$(extract_ops_per_sec "$tag_dir/stress-pipe.txt" "pipe")
    fork_ops=$(extract_ops_per_sec "$tag_dir/stress-fork.txt" "fork")

    printf "%-25s %8s %12s %12s %12s\n" \
        "$tag" "$status" "$cpu_ops" "$pipe_ops" "$fork_ops"
done

echo ""
echo "================================================================"

# ── Dump raw stress-ng output for debugging ──────────────────────────

echo ""
echo "── Raw stress-ng output ─────────────────────────────────────"
for tag_dir in "$RESULTS_DIR"/*/; do
    tag=$(basename "$tag_dir")
    echo ""
    echo "--- $tag ---"
    for f in "$tag_dir"/stress-*.txt; do
        if [ -f "$f" ]; then
            echo "  $(basename "$f"):"
            grep -E "bogo ops|completed|per sec" "$f" 2>/dev/null | sed 's/^/    /' || echo "    (no data)"
        fi
    done
done

echo ""
echo "Benchmark complete."
