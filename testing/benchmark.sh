#!/bin/bash
#
# benchmark.sh — Compare sched-ext scheduler performance.
#
# Runs a standard set of workloads under a given scheduler and records
# results in a machine-readable format.  Run once per scheduler, then
# compare the output files.
#
# Usage:
#   sudo ./testing/benchmark.sh <scheduler-binary> [results-dir]
#
# Examples:
#   # Standard cosmos (libbpf-rs + C BPF):
#   sudo ./testing/benchmark.sh \
#       ./scx/scheds/rust/scx_cosmos/target/release/scx_cosmos \
#       results/standard-cosmos
#
#   # Pure-Rust cosmos (aya + Rust BPF):
#   sudo ./testing/benchmark.sh \
#       ./scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos \
#       results/purerust-cosmos
#
#   # Compare:
#   ./testing/compare-results.sh results/standard-cosmos results/purerust-cosmos
#
# The script:
#   1. Starts the scheduler in the background
#   2. Waits for attachment (checks dmesg for sched_ext)
#   3. Runs each benchmark N times (configurable via BENCH_ITERATIONS)
#   4. Records raw output + extracted metrics
#   5. Stops the scheduler
#   6. Writes a summary JSON
#
# Environment variables:
#   BENCH_ITERATIONS — number of iterations per benchmark (default: 3)
#   BENCH_WARMUP     — warmup duration in seconds (default: 5)
#   BENCH_SETTLE     — settle time between benchmarks in seconds (default: 3)
#   BENCH_SKIP       — comma-separated list of benchmarks to skip
#   SCHED_ARGS       — extra arguments to pass to the scheduler
#   DRY_RUN          — set to "1" to print commands without running (default: 0)
#
# Prerequisites:
#   Required: stress-ng, schbench
#   Optional: hackbench, cyclictest, sysbench, perf
#   The script will skip benchmarks whose tools are not installed.
#
# Output structure:
#   <results-dir>/
#     summary.json         — all metrics in one file
#     meta.txt             — system info, scheduler, kernel version
#     raw/                 — raw benchmark output files
#       schbench-1.txt, schbench-2.txt, ...
#       stress-ng-cpu-1.txt, ...

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments & configuration
# ---------------------------------------------------------------------------
SCHEDULER_BIN="${1:-}"
RESULTS_DIR="${2:-results/$(date +%Y%m%d-%H%M%S)}"

BENCH_ITERATIONS="${BENCH_ITERATIONS:-3}"
BENCH_WARMUP="${BENCH_WARMUP:-5}"
BENCH_SETTLE="${BENCH_SETTLE:-3}"
BENCH_SKIP="${BENCH_SKIP:-}"
SCHED_ARGS="${SCHED_ARGS:-}"
DRY_RUN="${DRY_RUN:-0}"

if [[ -z "$SCHEDULER_BIN" ]]; then
    echo "Usage: sudo $0 <scheduler-binary> [results-dir]" >&2
    echo "" >&2
    echo "  scheduler-binary: Path to a sched-ext scheduler (e.g., scx_cosmos)" >&2
    echo "  results-dir:      Where to write results (default: results/<timestamp>)" >&2
    exit 1
fi

SCHEDULER_BIN="$(realpath "$SCHEDULER_BIN")"
SCHED_NAME="$(basename "$SCHEDULER_BIN")"

if [[ ! -x "$SCHEDULER_BIN" ]]; then
    echo "ERROR: $SCHEDULER_BIN is not executable or does not exist" >&2
    exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: Must run as root (scheduler attachment requires CAP_SYS_ADMIN)" >&2
    exit 1
fi

# Number of CPUs for workload sizing.
NCPUS="$(nproc)"
# Use half the CPUs for most benchmarks to avoid completely starving the
# scheduler userspace loop and the system.
HALF_CPUS=$(( NCPUS / 2 ))
if [[ "$HALF_CPUS" -lt 1 ]]; then
    HALF_CPUS=1
fi

# ---------------------------------------------------------------------------
# Tool detection
# ---------------------------------------------------------------------------
declare -A TOOLS
detect_tool() {
    local name="$1"
    local bin="${2:-$1}"
    if command -v "$bin" &>/dev/null; then
        TOOLS["$name"]="$(command -v "$bin")"
        return 0
    fi
    return 1
}

detect_tool schbench     || true
detect_tool stress-ng    stress-ng || true
detect_tool hackbench    || true
detect_tool cyclictest   || true
detect_tool sysbench     || true
detect_tool perf         || true

echo "=== Benchmark Tool Availability ==="
for tool in schbench stress-ng hackbench cyclictest sysbench perf; do
    if [[ -n "${TOOLS[$tool]:-}" ]]; then
        echo "  $tool: ${TOOLS[$tool]}"
    else
        echo "  $tool: NOT FOUND (benchmarks using this tool will be skipped)"
    fi
done
echo ""

should_skip() {
    local name="$1"
    if [[ -n "$BENCH_SKIP" ]]; then
        echo "$BENCH_SKIP" | tr ',' '\n' | grep -qx "$name" && return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Output setup
# ---------------------------------------------------------------------------
mkdir -p "$RESULTS_DIR/raw"

# Collect system metadata.
cat > "$RESULTS_DIR/meta.txt" <<EOF
scheduler: $SCHED_NAME
scheduler_binary: $SCHEDULER_BIN
scheduler_args: $SCHED_ARGS
kernel: $(uname -r)
hostname: $(hostname)
date: $(date -Iseconds)
cpus: $NCPUS
cpu_model: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")
memory_total_kb: $(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "unknown")
numa_nodes: $(ls -d /sys/devices/system/node/node* 2>/dev/null | wc -l)
iterations: $BENCH_ITERATIONS
warmup_seconds: $BENCH_WARMUP
settle_seconds: $BENCH_SETTLE
EOF

echo "=== System Info ==="
cat "$RESULTS_DIR/meta.txt"
echo ""

# Results accumulator (will be written as JSON at the end).
declare -A METRICS

# ---------------------------------------------------------------------------
# Scheduler lifecycle
# ---------------------------------------------------------------------------
SCHED_PID=""
SCHED_LOG="$RESULTS_DIR/raw/scheduler.log"

start_scheduler() {
    echo "--- Starting scheduler: $SCHED_NAME $SCHED_ARGS ---"

    if [[ "$DRY_RUN" == "1" ]]; then
        echo "[DRY RUN] Would start: $SCHEDULER_BIN $SCHED_ARGS"
        SCHED_PID="dry-run"
        return 0
    fi

    # shellcheck disable=SC2086
    $SCHEDULER_BIN $SCHED_ARGS > "$SCHED_LOG" 2>&1 &
    SCHED_PID=$!

    # Wait for the scheduler to attach by watching for the sched_ext
    # kernel message or the process producing output.
    local waited=0
    local max_wait=15
    while [[ $waited -lt $max_wait ]]; do
        # Check if process is still alive.
        if ! kill -0 "$SCHED_PID" 2>/dev/null; then
            echo "ERROR: Scheduler exited prematurely. Log:" >&2
            cat "$SCHED_LOG" >&2
            return 1
        fi

        # Check for attachment indicators.
        if dmesg 2>/dev/null | tail -20 | grep -q "sched_ext: BPF scheduler"; then
            echo "  Scheduler attached (detected via dmesg)."
            break
        fi

        # Also check the scheduler's own output for "attached" or "enabled".
        if grep -qi "attach\|enabled\|scheduler started" "$SCHED_LOG" 2>/dev/null; then
            echo "  Scheduler attached (detected via scheduler output)."
            break
        fi

        sleep 1
        waited=$((waited + 1))
    done

    if [[ $waited -ge $max_wait ]]; then
        echo "WARNING: Could not confirm scheduler attachment after ${max_wait}s."
        echo "         Proceeding anyway (scheduler PID=$SCHED_PID is still running)."
    fi

    # Warmup period: let the scheduler settle.
    echo "  Warming up for ${BENCH_WARMUP}s..."
    sleep "$BENCH_WARMUP"
    echo "  Warmup complete."
}

stop_scheduler() {
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "[DRY RUN] Would stop scheduler."
        return 0
    fi

    if [[ -n "$SCHED_PID" ]] && kill -0 "$SCHED_PID" 2>/dev/null; then
        echo "--- Stopping scheduler (PID=$SCHED_PID) ---"
        kill -TERM "$SCHED_PID" 2>/dev/null || true
        # Wait up to 10s for clean shutdown.
        local waited=0
        while kill -0 "$SCHED_PID" 2>/dev/null && [[ $waited -lt 10 ]]; do
            sleep 1
            waited=$((waited + 1))
        done
        if kill -0 "$SCHED_PID" 2>/dev/null; then
            echo "  Force-killing scheduler..."
            kill -KILL "$SCHED_PID" 2>/dev/null || true
        fi
        wait "$SCHED_PID" 2>/dev/null || true
        echo "  Scheduler stopped."
    fi
}

trap stop_scheduler EXIT

# ---------------------------------------------------------------------------
# Benchmark runner helpers
# ---------------------------------------------------------------------------

# Run a single benchmark iteration and capture output.
# Usage: run_iter <benchmark-name> <iteration> <command...>
run_iter() {
    local name="$1"
    local iter="$2"
    shift 2
    local outfile="$RESULTS_DIR/raw/${name}-${iter}.txt"

    if [[ "$DRY_RUN" == "1" ]]; then
        echo "  [DRY RUN] iter $iter: $*"
        return 0
    fi

    echo "  iter $iter: $*"
    # Run with /usr/bin/time for wall-clock timing.
    { /usr/bin/time -v "$@" ; } > "$outfile" 2>&1
    echo "  -> saved to $outfile"
}

# Store a metric value.
store_metric() {
    local key="$1"
    local value="$2"
    METRICS["$key"]="$value"
}

# Compute the median of a list of numbers (one per line on stdin).
median() {
    sort -n | awk '{a[NR]=$1} END {
        if (NR % 2 == 1) print a[(NR+1)/2];
        else print (a[NR/2] + a[NR/2+1]) / 2.0
    }'
}

# Settle between benchmarks.
settle() {
    if [[ "$DRY_RUN" != "1" ]] && [[ "$BENCH_SETTLE" -gt 0 ]]; then
        echo "  (settling ${BENCH_SETTLE}s)"
        sleep "$BENCH_SETTLE"
    fi
}

# ---------------------------------------------------------------------------
# Benchmark: schbench (scheduling latency)
# ---------------------------------------------------------------------------
# schbench measures wakeup latency under a messaging workload.
# It reports p50, p90, p95, p99, p99.5, p99.9 latencies in microseconds.
#
# Relevance: This directly measures the scheduler's dispatch latency.
# Lower is better. Differences here indicate overhead in the scheduling
# hot path (BPF program execution, map lookups, etc).
bench_schbench() {
    local name="schbench"
    if [[ -z "${TOOLS[schbench]:-}" ]]; then
        echo "SKIP: schbench not found"
        return
    fi
    if should_skip "$name"; then
        echo "SKIP: $name (in BENCH_SKIP)"
        return
    fi

    echo ""
    echo "=== Benchmark: schbench (scheduling latency) ==="

    # Use message threads = half CPUs, 1 worker per message thread,
    # 30-second runtime.  This creates a realistic messaging workload
    # that exercises the scheduler's dispatch path.
    local runtime=30
    local msg_threads="$HALF_CPUS"
    local workers=1

    for iter in $(seq 1 "$BENCH_ITERATIONS"); do
        settle
        run_iter "$name" "$iter" \
            schbench -m "$msg_threads" -t "$workers" -r "$runtime" -R
    done

    # Extract p99 latencies from all iterations.
    if [[ "$DRY_RUN" != "1" ]]; then
        local p50_median p99_median p999_median

        p50_median=$(for f in "$RESULTS_DIR/raw/${name}"-*.txt; do
            grep -E '^\s*50\.0th:' "$f" 2>/dev/null | awk '{print $2}'
        done | median)

        p99_median=$(for f in "$RESULTS_DIR/raw/${name}"-*.txt; do
            grep -E '^\s*99\.0th:' "$f" 2>/dev/null | awk '{print $2}'
        done | median)

        p999_median=$(for f in "$RESULTS_DIR/raw/${name}"-*.txt; do
            grep -E '^\s*99\.9th:' "$f" 2>/dev/null | awk '{print $2}'
        done | median)

        store_metric "schbench_p50_us" "${p50_median:-N/A}"
        store_metric "schbench_p99_us" "${p99_median:-N/A}"
        store_metric "schbench_p999_us" "${p999_median:-N/A}"

        echo "  Results (median of $BENCH_ITERATIONS runs):"
        echo "    p50:  ${p50_median:-N/A} us"
        echo "    p99:  ${p99_median:-N/A} us"
        echo "    p999: ${p999_median:-N/A} us"
    fi
}

# ---------------------------------------------------------------------------
# Benchmark: stress-ng cpu (pure compute throughput)
# ---------------------------------------------------------------------------
# Measures how many bogus operations per second the system can sustain
# under pure CPU load.  This tests the scheduler's ability to keep all
# CPUs busy without excessive overhead.
#
# Relevance: If the pure-Rust BPF programs have different instruction
# counts or map access patterns, it will show up as throughput differences
# under saturated CPU conditions.
bench_stress_ng_cpu() {
    local name="stress-ng-cpu"
    if [[ -z "${TOOLS[stress-ng]:-}" ]]; then
        echo "SKIP: stress-ng not found"
        return
    fi
    if should_skip "$name"; then
        echo "SKIP: $name (in BENCH_SKIP)"
        return
    fi

    echo ""
    echo "=== Benchmark: stress-ng cpu (compute throughput) ==="

    local runtime=30
    local workers="$HALF_CPUS"

    for iter in $(seq 1 "$BENCH_ITERATIONS"); do
        settle
        run_iter "$name" "$iter" \
            stress-ng --cpu "$workers" --cpu-method matrixprod \
                --metrics-brief --timeout "${runtime}s" --yaml /dev/null
    done

    # Extract bogo-ops/sec from stress-ng output.
    if [[ "$DRY_RUN" != "1" ]]; then
        local ops_median
        ops_median=$(for f in "$RESULTS_DIR/raw/${name}"-*.txt; do
            grep -E 'cpu\s' "$f" 2>/dev/null | awk '{print $(NF-1)}'
        done | median)

        store_metric "stress_ng_cpu_bogops_per_sec" "${ops_median:-N/A}"
        echo "  Results (median): ${ops_median:-N/A} bogo-ops/sec"
    fi
}

# ---------------------------------------------------------------------------
# Benchmark: stress-ng context switch (ctx switch overhead)
# ---------------------------------------------------------------------------
# Measures context switch rate.  Forces rapid context switches and
# reports how many per second the system can sustain.
#
# Relevance: This directly tests the sched_ext dispatch/enqueue hot path.
# The BPF program runs on every context switch, so differences in BPF
# program efficiency show up here.
bench_stress_ng_ctx() {
    local name="stress-ng-context"
    if [[ -z "${TOOLS[stress-ng]:-}" ]]; then
        echo "SKIP: stress-ng not found"
        return
    fi
    if should_skip "$name"; then
        echo "SKIP: $name (in BENCH_SKIP)"
        return
    fi

    echo ""
    echo "=== Benchmark: stress-ng context-switch (ctx switch overhead) ==="

    local runtime=20
    local workers="$HALF_CPUS"

    for iter in $(seq 1 "$BENCH_ITERATIONS"); do
        settle
        run_iter "$name" "$iter" \
            stress-ng --context "$workers" --metrics-brief \
                --timeout "${runtime}s" --yaml /dev/null
    done

    if [[ "$DRY_RUN" != "1" ]]; then
        local ops_median
        ops_median=$(for f in "$RESULTS_DIR/raw/${name}"-*.txt; do
            grep -E 'context\s' "$f" 2>/dev/null | awk '{print $(NF-1)}'
        done | median)

        store_metric "stress_ng_context_ops_per_sec" "${ops_median:-N/A}"
        echo "  Results (median): ${ops_median:-N/A} context-switches/sec"
    fi
}

# ---------------------------------------------------------------------------
# Benchmark: hackbench (scheduler scalability)
# ---------------------------------------------------------------------------
# hackbench creates groups of threads that pass messages through pipes
# or sockets, stressing the scheduler's ability to handle many runnable
# tasks efficiently.
#
# Relevance: Tests how well the scheduler handles task fan-out and
# contention.  The global DSQ vs per-CPU DSQ decision in cosmos is
# exercised heavily here.
bench_hackbench() {
    local name="hackbench"
    if [[ -z "${TOOLS[hackbench]:-}" ]]; then
        echo "SKIP: hackbench not found"
        return
    fi
    if should_skip "$name"; then
        echo "SKIP: $name (in BENCH_SKIP)"
        return
    fi

    echo ""
    echo "=== Benchmark: hackbench (scheduler scalability) ==="

    # Use thread mode (-T), pipe mode (-P), moderate group count.
    local groups=$(( HALF_CPUS / 2 ))
    if [[ "$groups" -lt 2 ]]; then
        groups=2
    fi
    local loops=1000

    for iter in $(seq 1 "$BENCH_ITERATIONS"); do
        settle
        run_iter "$name" "$iter" \
            hackbench -T -P -g "$groups" -l "$loops"
    done

    if [[ "$DRY_RUN" != "1" ]]; then
        local time_median
        time_median=$(for f in "$RESULTS_DIR/raw/${name}"-*.txt; do
            grep -i 'Time:' "$f" 2>/dev/null | awk '{print $2}'
        done | median)

        store_metric "hackbench_time_sec" "${time_median:-N/A}"
        echo "  Results (median): ${time_median:-N/A} seconds"
    fi
}

# ---------------------------------------------------------------------------
# Benchmark: cyclictest (worst-case latency under load)
# ---------------------------------------------------------------------------
# cyclictest measures timer interrupt latency, which reveals scheduling
# jitter.  We run it alongside a CPU stress workload.
#
# Relevance: Tests the scheduler's worst-case behavior.  A scheduler
# that adds overhead to the dispatch path will show higher tail latencies.
bench_cyclictest() {
    local name="cyclictest"
    if [[ -z "${TOOLS[cyclictest]:-}" ]]; then
        echo "SKIP: cyclictest not found"
        return
    fi
    if should_skip "$name"; then
        echo "SKIP: $name (in BENCH_SKIP)"
        return
    fi

    echo ""
    echo "=== Benchmark: cyclictest (latency under load) ==="

    local runtime=30
    local threads=4

    for iter in $(seq 1 "$BENCH_ITERATIONS"); do
        settle

        local outfile="$RESULTS_DIR/raw/${name}-${iter}.txt"

        if [[ "$DRY_RUN" == "1" ]]; then
            echo "  [DRY RUN] iter $iter: cyclictest + stress-ng background"
            continue
        fi

        # Start a CPU stress background load.
        stress-ng --cpu "$HALF_CPUS" --timeout "$((runtime + 5))s" \
            --quiet &>/dev/null &
        local stress_pid=$!

        echo "  iter $iter: cyclictest -t $threads -D ${runtime}s + stress-ng background"
        cyclictest -t "$threads" -D "${runtime}s" -q --mlockall \
            > "$outfile" 2>&1 || true

        # Stop the background load.
        kill "$stress_pid" 2>/dev/null || true
        wait "$stress_pid" 2>/dev/null || true

        echo "  -> saved to $outfile"
    done

    if [[ "$DRY_RUN" != "1" ]]; then
        # cyclictest -q prints: T: N ... Min: X Avg: Y Max: Z
        local max_median avg_median
        max_median=$(for f in "$RESULTS_DIR/raw/${name}"-*.txt; do
            grep '^T:' "$f" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="Max:") print $(i+1)}' | sort -n | tail -1
        done | median)

        avg_median=$(for f in "$RESULTS_DIR/raw/${name}"-*.txt; do
            grep '^T:' "$f" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="Avg:") print $(i+1)}' | sort -n | tail -1
        done | median)

        store_metric "cyclictest_max_us" "${max_median:-N/A}"
        store_metric "cyclictest_avg_us" "${avg_median:-N/A}"
        echo "  Results (median of worst-thread):"
        echo "    Avg: ${avg_median:-N/A} us"
        echo "    Max: ${max_median:-N/A} us"
    fi
}

# ---------------------------------------------------------------------------
# Benchmark: stress-ng pipe (IPC throughput)
# ---------------------------------------------------------------------------
# Measures pipe throughput — how many messages per second can flow through
# pipes.  This exercises the wake-sync path in cosmos: a writer wakes the
# reader on the same CPU for cache locality.
#
# Relevance: The `no_wake_sync` flag in cosmos controls whether the
# scheduler does direct dispatch on synchronous wakeups.  This benchmark
# directly tests that code path.
bench_stress_ng_pipe() {
    local name="stress-ng-pipe"
    if [[ -z "${TOOLS[stress-ng]:-}" ]]; then
        echo "SKIP: stress-ng not found"
        return
    fi
    if should_skip "$name"; then
        echo "SKIP: $name (in BENCH_SKIP)"
        return
    fi

    echo ""
    echo "=== Benchmark: stress-ng pipe (IPC / wake-sync) ==="

    local runtime=20
    local workers="$HALF_CPUS"

    for iter in $(seq 1 "$BENCH_ITERATIONS"); do
        settle
        run_iter "$name" "$iter" \
            stress-ng --pipe "$workers" --metrics-brief \
                --timeout "${runtime}s" --yaml /dev/null
    done

    if [[ "$DRY_RUN" != "1" ]]; then
        local ops_median
        ops_median=$(for f in "$RESULTS_DIR/raw/${name}"-*.txt; do
            grep -E 'pipe\s' "$f" 2>/dev/null | awk '{print $(NF-1)}'
        done | median)

        store_metric "stress_ng_pipe_ops_per_sec" "${ops_median:-N/A}"
        echo "  Results (median): ${ops_median:-N/A} pipe-ops/sec"
    fi
}

# ---------------------------------------------------------------------------
# Benchmark: kernel compile (real-world mixed workload)
# ---------------------------------------------------------------------------
# A kernel compile is the canonical mixed workload: CPU-intensive
# compilation, I/O for reading source/writing objects, many short-lived
# processes (the compiler invocations), and moderate parallelism.
#
# We build a minimal kernel config to keep runtime reasonable.
bench_kernel_compile() {
    local name="kernel-compile"
    if should_skip "$name"; then
        echo "SKIP: $name (in BENCH_SKIP)"
        return
    fi

    # Check prerequisites.
    if ! command -v make &>/dev/null; then
        echo "SKIP: kernel-compile (make not found)"
        return
    fi

    # Look for a kernel source tree.
    local ksrc=""
    for candidate in /usr/src/linux /lib/modules/$(uname -r)/build; do
        if [[ -f "$candidate/Makefile" ]]; then
            ksrc="$candidate"
            break
        fi
    done

    if [[ -z "$ksrc" ]]; then
        echo "SKIP: kernel-compile (no kernel source at /usr/src/linux or build dir)"
        return
    fi

    echo ""
    echo "=== Benchmark: kernel compile (mixed workload) ==="
    echo "  source: $ksrc"

    local jobs="$HALF_CPUS"

    for iter in $(seq 1 "$BENCH_ITERATIONS"); do
        settle

        local outfile="$RESULTS_DIR/raw/${name}-${iter}.txt"

        if [[ "$DRY_RUN" == "1" ]]; then
            echo "  [DRY RUN] iter $iter: make -C $ksrc -j$jobs"
            continue
        fi

        # Clean first (we want to time a full build).
        make -C "$ksrc" -j"$jobs" clean &>/dev/null 2>&1 || true

        echo "  iter $iter: make -j$jobs (tinyconfig)"
        { /usr/bin/time -v make -C "$ksrc" -j"$jobs" tinyconfig && \
          /usr/bin/time -v make -C "$ksrc" -j"$jobs" ; } \
            > "$outfile" 2>&1

        echo "  -> saved to $outfile"
    done

    if [[ "$DRY_RUN" != "1" ]]; then
        local time_median
        time_median=$(for f in "$RESULTS_DIR/raw/${name}"-*.txt; do
            grep 'Elapsed (wall clock)' "$f" 2>/dev/null | tail -1 | \
                sed 's/.*: //' | awk -F: '{
                    if (NF==3) print $1*3600+$2*60+$3;
                    else if (NF==2) print $1*60+$2;
                    else print $1
                }'
        done | median)

        store_metric "kernel_compile_time_sec" "${time_median:-N/A}"
        echo "  Results (median): ${time_median:-N/A} seconds"
    fi
}

# ---------------------------------------------------------------------------
# Benchmark: perf sched stats (scheduling internals)
# ---------------------------------------------------------------------------
# If perf is available, record scheduling stats for a 10-second window
# under mixed load.  This gives us context switch counts, migration
# counts, and scheduler latency from the kernel's perspective.
bench_perf_sched() {
    local name="perf-sched"
    if [[ -z "${TOOLS[perf]:-}" ]]; then
        echo "SKIP: perf not found"
        return
    fi
    if should_skip "$name"; then
        echo "SKIP: $name (in BENCH_SKIP)"
        return
    fi

    echo ""
    echo "=== Benchmark: perf sched stats ==="

    local runtime=15
    local outfile="$RESULTS_DIR/raw/${name}.txt"

    if [[ "$DRY_RUN" == "1" ]]; then
        echo "  [DRY RUN] perf stat + stress-ng"
        return
    fi

    # Run a mixed workload and capture scheduling statistics.
    stress-ng --cpu "$HALF_CPUS" --pipe 4 --timeout "$((runtime + 3))s" \
        --quiet &>/dev/null &
    local stress_pid=$!

    # Capture system-wide scheduling stats.
    perf stat -e 'sched:sched_switch,sched:sched_migrate_task,sched:sched_wakeup' \
        -a -- sleep "$runtime" > "$outfile" 2>&1 || true

    kill "$stress_pid" 2>/dev/null || true
    wait "$stress_pid" 2>/dev/null || true

    # Extract key counters.
    local switches migrations wakeups
    switches=$(grep 'sched_switch' "$outfile" 2>/dev/null | awk '{gsub(/,/,"",$1); print $1}' || echo "N/A")
    migrations=$(grep 'sched_migrate_task' "$outfile" 2>/dev/null | awk '{gsub(/,/,"",$1); print $1}' || echo "N/A")
    wakeups=$(grep 'sched_wakeup' "$outfile" 2>/dev/null | awk '{gsub(/,/,"",$1); print $1}' || echo "N/A")

    store_metric "perf_context_switches" "${switches:-N/A}"
    store_metric "perf_migrations" "${migrations:-N/A}"
    store_metric "perf_wakeups" "${wakeups:-N/A}"

    echo "  Context switches: ${switches:-N/A}"
    echo "  Task migrations:  ${migrations:-N/A}"
    echo "  Wakeups:          ${wakeups:-N/A}"
}

# ---------------------------------------------------------------------------
# Write results
# ---------------------------------------------------------------------------
write_summary() {
    local outfile="$RESULTS_DIR/summary.json"

    echo ""
    echo "=== Writing summary to $outfile ==="

    # Build JSON manually (no jq dependency required).
    {
        echo "{"
        echo "  \"scheduler\": \"$SCHED_NAME\","
        echo "  \"scheduler_args\": \"$SCHED_ARGS\","
        echo "  \"kernel\": \"$(uname -r)\","
        echo "  \"date\": \"$(date -Iseconds)\","
        echo "  \"cpus\": $NCPUS,"
        echo "  \"iterations\": $BENCH_ITERATIONS,"
        echo "  \"metrics\": {"

        local first=true
        for key in $(echo "${!METRICS[@]}" | tr ' ' '\n' | sort); do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            local val="${METRICS[$key]}"
            # Try to output as number if it looks numeric, otherwise string.
            if [[ "$val" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                printf "    \"%s\": %s" "$key" "$val"
            else
                printf "    \"%s\": \"%s\"" "$key" "$val"
            fi
        done
        echo ""
        echo "  }"
        echo "}"
    } > "$outfile"

    echo "  Done."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo " Scheduler Benchmark Suite"
echo " Scheduler: $SCHED_NAME"
echo " Iterations: $BENCH_ITERATIONS"
echo " Results: $RESULTS_DIR"
echo "================================================================"
echo ""

start_scheduler

# Run all benchmarks in a defined order.
# The order is chosen to minimize interference:
#   1. Latency benchmarks first (most sensitive to system state)
#   2. Throughput benchmarks
#   3. Mixed workloads last
bench_schbench
bench_cyclictest
bench_stress_ng_ctx
bench_stress_ng_pipe
bench_stress_ng_cpu
bench_hackbench
bench_kernel_compile
bench_perf_sched

write_summary

echo ""
echo "================================================================"
echo " Benchmark Complete"
echo " Results in: $RESULTS_DIR"
echo " Summary:    $RESULTS_DIR/summary.json"
echo "================================================================"
echo ""
echo "=== Quick Results ==="
for key in $(echo "${!METRICS[@]}" | tr ' ' '\n' | sort); do
    printf "  %-40s %s\n" "$key" "${METRICS[$key]}"
done
echo ""
echo "To compare two runs:"
echo "  ./testing/compare-results.sh <dir1>/summary.json <dir2>/summary.json"
