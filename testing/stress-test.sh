#!/bin/bash
# stress-test.sh — Run scx_mitosis under sustained stress workload.
#
# This script runs INSIDE a virtme-ng VM. It:
# 1. Starts scx_mitosis_rs as the system scheduler
# 2. Applies mixed CPU/IO/memory stress workloads
# 3. Monitors scheduler health every 30 seconds
# 4. Collects performance metrics every minute
# 5. Reports results at exit
#
# Usage: ./testing/stress-test.sh [duration_seconds]
#        Default: 1800 (30 minutes)

set -euo pipefail

DURATION="${1:-1800}"
SCHEDULER_BIN="${SCHEDULER_BIN:-$(dirname "$0")/../scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs}"
SCHEDULER_BIN="$(realpath "$SCHEDULER_BIN")"
LOGDIR="/tmp/mitosis-stress-$$"
mkdir -p "$LOGDIR"

# ── Metrics collection ───────────────────────────────────────────────

collect_metrics() {
    local ts
    ts=$(date +%s)
    local uptime
    uptime=$(cat /proc/uptime | cut -d' ' -f1)
    local loadavg
    loadavg=$(cat /proc/loadavg)
    local ctxt
    ctxt=$(grep '^ctxt' /proc/stat | awk '{print $2}')
    local procs_running
    procs_running=$(grep '^procs_running' /proc/stat | awk '{print $2}')
    local procs_blocked
    procs_blocked=$(grep '^procs_blocked' /proc/stat | awk '{print $2}')

    echo "$ts $uptime $loadavg ctxt=$ctxt run=$procs_running blk=$procs_blocked"
}

# ── Check scheduler is attached ──────────────────────────────────────

check_scheduler() {
    if [ -f /sys/kernel/sched_ext/root/ops ]; then
        local ops
        ops=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none")
        if [ "$ops" = "mitosis" ]; then
            return 0
        fi
    fi
    return 1
}

# ── Main ─────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════"
echo "  MITOSIS STRESS TEST"
echo "  Duration: ${DURATION}s  $(date)"
echo "  Kernel: $(uname -r)"
echo "  CPUs: $(nproc)"
echo "═══════════════════════════════════════════════════════════"

# Baseline metrics
echo ""
echo "── Baseline ──"
collect_metrics | tee "$LOGDIR/metrics.log"
echo ""

# Start scheduler
echo "── Starting scx_mitosis_rs ──"
"$SCHEDULER_BIN" 2>&1 | tee "$LOGDIR/scheduler.log" &
SCHED_PID=$!
sleep 3

if ! kill -0 "$SCHED_PID" 2>/dev/null; then
    echo "FATAL: Scheduler failed to start"
    cat "$LOGDIR/scheduler.log"
    exit 1
fi

if check_scheduler; then
    echo "✅ Scheduler attached: $(cat /sys/kernel/sched_ext/root/ops)"
    echo "   sched_ext state: $(cat /sys/kernel/sched_ext/state)"
else
    echo "⚠️  Scheduler process running but not attached (may still be loading)"
fi

# Record initial context switch count
INITIAL_CTXT=$(grep '^ctxt' /proc/stat | awk '{print $2}')
START_TIME=$(date +%s)

# ── Start stress workloads ───────────────────────────────────────────

echo ""
echo "── Starting stress workloads ──"

NCPU=$(nproc)
# Scale stress to available CPUs
STRESS_CPU=$((NCPU / 2))
[ "$STRESS_CPU" -lt 2 ] && STRESS_CPU=2
STRESS_IO=$((NCPU / 4))
[ "$STRESS_IO" -lt 1 ] && STRESS_IO=1
STRESS_VM=$((NCPU / 4))
[ "$STRESS_VM" -lt 1 ] && STRESS_VM=1

# Compute stress duration (shorter than test to leave cleanup time)
STRESS_DUR=$((DURATION - 30))
[ "$STRESS_DUR" -lt 60 ] && STRESS_DUR=60

if command -v stress-ng &>/dev/null; then
    echo "  stress-ng: --cpu $STRESS_CPU --io $STRESS_IO --vm $STRESS_VM --vm-bytes 32M --timeout ${STRESS_DUR}s"
    stress-ng --cpu "$STRESS_CPU" --io "$STRESS_IO" --vm "$STRESS_VM" \
              --vm-bytes 32M --timeout "${STRESS_DUR}s" \
              --metrics-brief 2>&1 | tee "$LOGDIR/stress-ng.log" &
    STRESS_PID=$!
else
    echo "  stress-ng not available, using shell-based stress"
    # CPU stress
    for i in $(seq "$STRESS_CPU"); do
        while true; do true; done &
    done
    # I/O stress
    for i in $(seq "$STRESS_IO"); do
        while true; do dd if=/dev/urandom of=/dev/null bs=4k count=256 2>/dev/null; done &
    done
    # Filesystem stress
    while true; do ls -laR /proc > /dev/null 2>&1; done &
    STRESS_PID=$!
fi

# Also add context-switch-heavy workload (many short-lived processes)
echo "  fork-bomb-lite: continuous short-lived processes"
(
    while true; do
        for i in $(seq 20); do
            /bin/true &
        done
        wait
        sleep 0.1
    done
) &
FORK_PID=$!

echo ""
echo "── Monitoring (every 30s) ──"

# ── Monitoring loop ──────────────────────────────────────────────────

CHECKS=0
FAILURES=0
LAST_MINUTE_REPORT=0

while true; do
    ELAPSED=$(( $(date +%s) - START_TIME ))

    if [ "$ELAPSED" -ge "$DURATION" ]; then
        break
    fi

    sleep 30
    CHECKS=$((CHECKS + 1))

    # Check scheduler is still alive
    if ! kill -0 "$SCHED_PID" 2>/dev/null; then
        echo "❌ SCHEDULER CRASHED at ${ELAPSED}s!"
        FAILURES=$((FAILURES + 1))
        # Try to capture any error output
        echo "  Last scheduler output:"
        tail -5 "$LOGDIR/scheduler.log" 2>/dev/null || true
        break
    fi

    # Check scheduler is still attached
    if ! check_scheduler; then
        echo "❌ SCHEDULER DETACHED at ${ELAPSED}s!"
        echo "  sched_ext state: $(cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'unknown')"
        FAILURES=$((FAILURES + 1))
        break
    fi

    # Collect metrics every 30s
    METRICS=$(collect_metrics)
    echo "  [${ELAPSED}s] $METRICS" | tee -a "$LOGDIR/metrics.log"

    # Detailed report every 60s
    if [ $((ELAPSED - LAST_MINUTE_REPORT)) -ge 60 ]; then
        CURRENT_CTXT=$(grep '^ctxt' /proc/stat | awk '{print $2}')
        CTXT_DELTA=$((CURRENT_CTXT - INITIAL_CTXT))
        CTXT_PER_SEC=$((CTXT_DELTA / (ELAPSED + 1)))
        echo "  [${ELAPSED}s] context_switches/s: ~${CTXT_PER_SEC}"
        LAST_MINUTE_REPORT=$ELAPSED
    fi
done

# ── Cleanup ──────────────────────────────────────────────────────────

echo ""
echo "── Stopping workloads ──"

# Stop stress workloads
kill "$FORK_PID" 2>/dev/null || true
if [ -n "${STRESS_PID:-}" ]; then
    kill "$STRESS_PID" 2>/dev/null || true
fi
# Kill any remaining background jobs
jobs -p | xargs -r kill 2>/dev/null || true
wait 2>/dev/null || true

# Final metrics
FINAL_TIME=$(date +%s)
TOTAL_ELAPSED=$((FINAL_TIME - START_TIME))
FINAL_CTXT=$(grep '^ctxt' /proc/stat | awk '{print $2}')
TOTAL_CTXT=$((FINAL_CTXT - INITIAL_CTXT))
CTXT_PER_SEC=$((TOTAL_CTXT / (TOTAL_ELAPSED + 1)))

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  RESULTS"
echo "═══════════════════════════════════════════════════════════"
echo "  Duration:          ${TOTAL_ELAPSED}s"
echo "  Health checks:     $CHECKS passed, $FAILURES failed"
echo "  Context switches:  $TOTAL_CTXT total (~${CTXT_PER_SEC}/s)"
echo "  Final load avg:    $(cat /proc/loadavg)"
echo "  Scheduler status:  $(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo 'detached')"
echo "  sched_ext state:   $(cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'unknown')"

if [ "$FAILURES" -eq 0 ]; then
    echo ""
    echo "  ✅ STRESS TEST PASSED"
else
    echo ""
    echo "  ❌ STRESS TEST FAILED ($FAILURES failures)"
fi
echo "═══════════════════════════════════════════════════════════"

# Stop scheduler
kill "$SCHED_PID" 2>/dev/null || true
wait "$SCHED_PID" 2>/dev/null || true

exit "$FAILURES"
