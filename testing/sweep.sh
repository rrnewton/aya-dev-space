#!/bin/bash
#
# sweep.sh — Run full benchmark sweep across EEVDF, C Cosmos, Rust Cosmos
#
# Usage: sudo ./testing/sweep.sh <results-base-dir> [c-cosmos-bin] [rust-cosmos-bin]
#
set -euo pipefail

RESULTS_BASE="${1:?Usage: sweep.sh <results-base-dir> [c-cosmos-bin] [rust-cosmos-bin]}"
C_COSMOS="${2:-scx/target/release/scx_cosmos}"
RUST_COSMOS="${3:-scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos}"

ITERATIONS="${BENCH_ITERATIONS:-3}"
WARMUP=5
SETTLE=3

# Workload parameters
SCHBENCH_GROUPS_SMALL=4
SCHBENCH_GROUPS_LARGE=16
SCHBENCH_DURATION=10
STRESS_WORKERS=4
STRESS_CPU_WORKERS=8
STRESS_DURATION=10

KERNEL=$(uname -r)
CPUS=$(nproc)
DATE=$(date -Iseconds)

echo "=== Benchmark Sweep ==="
echo "Kernel:     $KERNEL"
echo "CPUs:       $CPUS"
echo "Iterations: $ITERATIONS"
echo "Date:       $DATE"
echo ""

# ---------------------------------------------------------------------------
# Helper: run one benchmark, take median
# ---------------------------------------------------------------------------
run_schbench() {
    local groups=$1 iter=$2 outfile=$3
    schbench -m "$groups" -r "$SCHBENCH_DURATION" 2>&1 | tee "$outfile"
}

extract_schbench_p99_wakeup() {
    grep -A1 "Wakeup Latencies" "$1" | grep "99.0th" | tail -1 | awk '{print $2}'
}

extract_schbench_p99_request() {
    grep -A5 "Request Latencies" "$1" | grep "99.0th" | tail -1 | awk '{print $2}'
}

extract_schbench_rps() {
    grep "average rps" "$1" | tail -1 | awk '{print $3}'
}

run_stressng() {
    local stressor=$1 workers=$2 duration=$3 outfile=$4
    stress-ng --"$stressor" "$workers" -t "$duration" --metrics-brief 2>&1 | tee "$outfile"
}

extract_stressng_ops() {
    grep -E "^\s*stress-ng.*metrc.*$1" "$2" | tail -1 | awk '{print $7}'
}

median() {
    # Takes a list of numbers as args, returns median
    local sorted=($(printf '%s\n' "$@" | sort -g))
    local n=${#sorted[@]}
    echo "${sorted[$((n/2))]}"
}

# ---------------------------------------------------------------------------
# run_suite: run all benchmarks once, write to a directory
# ---------------------------------------------------------------------------
run_suite() {
    local label=$1 dir=$2
    mkdir -p "$dir/raw"

    echo ""
    echo "================================================================"
    echo "=== $label ==="
    echo "================================================================"
    echo ""

    local wakeup_4=() request_4=() rps_4=()
    local wakeup_16=() request_16=() rps_16=()
    local ctx_ops=() pipe_ops=() cpu_ops=()

    for i in $(seq 1 "$ITERATIONS"); do
        echo "--- Iteration $i/$ITERATIONS ---"

        # schbench small
        echo "  schbench ${SCHBENCH_GROUPS_SMALL} groups..."
        run_schbench "$SCHBENCH_GROUPS_SMALL" "$i" "$dir/raw/schbench-4-$i.txt" > /dev/null 2>&1
        wakeup_4+=($(extract_schbench_p99_wakeup "$dir/raw/schbench-4-$i.txt"))
        request_4+=($(extract_schbench_p99_request "$dir/raw/schbench-4-$i.txt"))
        rps_4+=($(extract_schbench_rps "$dir/raw/schbench-4-$i.txt"))
        sleep "$SETTLE"

        # schbench large
        echo "  schbench ${SCHBENCH_GROUPS_LARGE} groups..."
        run_schbench "$SCHBENCH_GROUPS_LARGE" "$i" "$dir/raw/schbench-16-$i.txt" > /dev/null 2>&1
        wakeup_16+=($(extract_schbench_p99_wakeup "$dir/raw/schbench-16-$i.txt"))
        request_16+=($(extract_schbench_p99_request "$dir/raw/schbench-16-$i.txt"))
        rps_16+=($(extract_schbench_rps "$dir/raw/schbench-16-$i.txt"))
        sleep "$SETTLE"

        # context switch
        echo "  stress-ng context..."
        run_stressng context "$STRESS_WORKERS" "$STRESS_DURATION" "$dir/raw/context-$i.txt" > /dev/null 2>&1
        ctx_ops+=($(extract_stressng_ops context "$dir/raw/context-$i.txt"))
        sleep "$SETTLE"

        # pipe
        echo "  stress-ng pipe..."
        run_stressng pipe "$STRESS_WORKERS" "$STRESS_DURATION" "$dir/raw/pipe-$i.txt" > /dev/null 2>&1
        pipe_ops+=($(extract_stressng_ops pipe "$dir/raw/pipe-$i.txt"))
        sleep "$SETTLE"

        # cpu
        echo "  stress-ng cpu..."
        run_stressng cpu "$STRESS_CPU_WORKERS" "$STRESS_DURATION" "$dir/raw/cpu-$i.txt" > /dev/null 2>&1
        cpu_ops+=($(extract_stressng_ops cpu "$dir/raw/cpu-$i.txt"))
        sleep "$SETTLE"
    done

    # Compute medians
    local m_wakeup_4=$(median "${wakeup_4[@]}")
    local m_request_4=$(median "${request_4[@]}")
    local m_rps_4=$(median "${rps_4[@]}")
    local m_wakeup_16=$(median "${wakeup_16[@]}")
    local m_request_16=$(median "${request_16[@]}")
    local m_rps_16=$(median "${rps_16[@]}")
    local m_ctx=$(median "${ctx_ops[@]}")
    local m_pipe=$(median "${pipe_ops[@]}")
    local m_cpu=$(median "${cpu_ops[@]}")

    # Write summary
    cat > "$dir/summary.json" <<EOF
{
  "label": "$label",
  "kernel": "$KERNEL",
  "cpus": $CPUS,
  "iterations": $ITERATIONS,
  "date": "$DATE",
  "schbench_4grp": {
    "wakeup_p99_us": $m_wakeup_4,
    "request_p99_us": $m_request_4,
    "avg_rps": $m_rps_4,
    "raw_wakeup": [$(IFS=,; echo "${wakeup_4[*]}")],
    "raw_request": [$(IFS=,; echo "${request_4[*]}")],
    "raw_rps": [$(IFS=,; echo "${rps_4[*]}")]
  },
  "schbench_16grp": {
    "wakeup_p99_us": $m_wakeup_16,
    "request_p99_us": $m_request_16,
    "avg_rps": $m_rps_16,
    "raw_wakeup": [$(IFS=,; echo "${wakeup_16[*]}")],
    "raw_request": [$(IFS=,; echo "${request_16[*]}")],
    "raw_rps": [$(IFS=,; echo "${rps_16[*]}")]
  },
  "context_switch": {
    "ops_per_sec": $m_ctx,
    "raw": [$(IFS=,; echo "${ctx_ops[*]}")]
  },
  "pipe": {
    "ops_per_sec": $m_pipe,
    "raw": [$(IFS=,; echo "${pipe_ops[*]}")]
  },
  "cpu": {
    "bogo_ops_per_sec": $m_cpu,
    "raw": [$(IFS=,; echo "${cpu_ops[*]}")]
  }
}
EOF

    echo ""
    echo "=== $label Results (median of $ITERATIONS iterations) ==="
    printf "  %-30s %s\n" "schbench 4grp wakeup p99:" "${m_wakeup_4} us"
    printf "  %-30s %s\n" "schbench 4grp request p99:" "${m_request_4} us"
    printf "  %-30s %s\n" "schbench 4grp avg RPS:" "${m_rps_4}"
    printf "  %-30s %s\n" "schbench 16grp wakeup p99:" "${m_wakeup_16} us"
    printf "  %-30s %s\n" "schbench 16grp request p99:" "${m_request_16} us"
    printf "  %-30s %s\n" "schbench 16grp avg RPS:" "${m_rps_16}"
    printf "  %-30s %s\n" "context switch ops/sec:" "${m_ctx}"
    printf "  %-30s %s\n" "pipe ops/sec:" "${m_pipe}"
    printf "  %-30s %s\n" "cpu bogo ops/sec:" "${m_cpu}"
    echo ""
}

# ---------------------------------------------------------------------------
# 1. EEVDF (no scheduler)
# ---------------------------------------------------------------------------
echo ">>> Ensuring no sched_ext scheduler is running..."
# Kill any running sched_ext schedulers
pkill -f scx_cosmos 2>/dev/null || true
sleep 2

run_suite "EEVDF (built-in)" "$RESULTS_BASE/eevdf"

# ---------------------------------------------------------------------------
# 2. C Cosmos
# ---------------------------------------------------------------------------
echo ">>> Starting C Cosmos..."
"$C_COSMOS" &
SCHED_PID=$!
sleep "$WARMUP"

# Verify it's running
if ! kill -0 "$SCHED_PID" 2>/dev/null; then
    echo "ERROR: C Cosmos failed to start"
    wait "$SCHED_PID" || true
    exit 1
fi

run_suite "C Cosmos (libbpf-rs + C BPF)" "$RESULTS_BASE/c-cosmos"

kill "$SCHED_PID" 2>/dev/null || true
wait "$SCHED_PID" 2>/dev/null || true
sleep 3

# ---------------------------------------------------------------------------
# 3. Rust Cosmos
# ---------------------------------------------------------------------------
echo ">>> Starting Rust Cosmos..."
"$RUST_COSMOS" &
SCHED_PID=$!
sleep "$WARMUP"

# Verify it's running
if ! kill -0 "$SCHED_PID" 2>/dev/null; then
    echo "ERROR: Rust Cosmos failed to start"
    wait "$SCHED_PID" || true
    exit 1
fi

run_suite "Rust Cosmos (aya + Rust BPF)" "$RESULTS_BASE/rust-cosmos"

kill "$SCHED_PID" 2>/dev/null || true
wait "$SCHED_PID" 2>/dev/null || true
sleep 3

# ---------------------------------------------------------------------------
# Summary comparison
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "=== COMPARISON TABLE ==="
echo "================================================================"
echo ""

# Read summaries
for metric in \
    "schbench_4grp.wakeup_p99_us:schbench 4grp wakeup p99 (us)" \
    "schbench_4grp.request_p99_us:schbench 4grp request p99 (us)" \
    "schbench_4grp.avg_rps:schbench 4grp avg RPS" \
    "schbench_16grp.wakeup_p99_us:schbench 16grp wakeup p99 (us)" \
    "schbench_16grp.request_p99_us:schbench 16grp request p99 (us)" \
    "schbench_16grp.avg_rps:schbench 16grp avg RPS" \
    "context_switch.ops_per_sec:context switch (ops/sec)" \
    "pipe.ops_per_sec:pipe (ops/sec)" \
    "cpu.bogo_ops_per_sec:cpu compute (bogo ops/sec)"; do

    key="${metric%%:*}"
    label="${metric#*:}"

    eevdf=$(python3 -c "import json; d=json.load(open('$RESULTS_BASE/eevdf/summary.json')); keys='$key'.split('.'); v=d; exec('for k in keys: v=v[k]'); print(v)" 2>/dev/null || echo "N/A")
    ccosmos=$(python3 -c "import json; d=json.load(open('$RESULTS_BASE/c-cosmos/summary.json')); keys='$key'.split('.'); v=d; exec('for k in keys: v=v[k]'); print(v)" 2>/dev/null || echo "N/A")
    rcosmos=$(python3 -c "import json; d=json.load(open('$RESULTS_BASE/rust-cosmos/summary.json')); keys='$key'.split('.'); v=d; exec('for k in keys: v=v[k]'); print(v)" 2>/dev/null || echo "N/A")

    printf "  %-35s  %12s  %12s  %12s\n" "$label" "$eevdf" "$ccosmos" "$rcosmos"
done

echo ""
echo "=== Sweep complete ==="
echo "Results in: $RESULTS_BASE/"
