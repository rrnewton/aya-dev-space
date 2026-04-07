#!/bin/bash
# mitosis-stress-combo.sh — Combined scheduler + stress workload
# This is the "binary" that run-in-vm.sh will execute.
# It starts the scheduler, then runs stress workloads alongside it.

set -euo pipefail

SCHEDULER_DIR="$(cd "$(dirname "$0")" && pwd)/../scx/scheds/rust_only/scx_mitosis/target/release"
SCHEDULER_BIN="$SCHEDULER_DIR/scx_mitosis_rs"

echo "═══ MITOSIS STRESS COMBO TEST ═══"
echo "Kernel: $(uname -r)"
echo "CPUs: $(nproc)"
echo "Date: $(date)"
echo ""

# Start scheduler in background
echo "Starting scx_mitosis_rs..."
"$SCHEDULER_BIN" &
SCHED_PID=$!
sleep 3

# Verify scheduler attached
if [ -f /sys/kernel/sched_ext/root/ops ]; then
    echo "Scheduler attached: $(cat /sys/kernel/sched_ext/root/ops)"
else
    echo "WARNING: sched_ext/root/ops not found"
fi

# Record baseline
INITIAL_CTXT=$(grep '^ctxt' /proc/stat | awk '{print $2}')
START_TIME=$(date +%s)

# Start stress workloads
echo ""
echo "Starting stress workloads..."

# CPU stress: spin loops
NCPU=$(nproc)
CPU_WORKERS=$((NCPU / 2))
[ "$CPU_WORKERS" -lt 2 ] && CPU_WORKERS=2
echo "  CPU workers: $CPU_WORKERS"
for i in $(seq "$CPU_WORKERS"); do
    while true; do : ; done &
done

# Fork stress: many short-lived processes
echo "  Fork stress: rapid process creation"
(while true; do for i in $(seq 10); do /bin/true & done; wait; done) &

# I/O stress: urandom reads
echo "  I/O stress: /dev/urandom reads"
(while true; do dd if=/dev/urandom of=/dev/null bs=4k count=64 2>/dev/null; done) &

# Memory pressure: allocate and touch pages
echo "  Memory stress: allocation patterns"
(while true; do head -c 16M /dev/urandom > /dev/null; done) &

echo ""
echo "Workloads running. Monitoring scheduler health..."

# Monitor loop: check scheduler every 30 seconds
CHECKS=0
while true; do
    sleep 30
    CHECKS=$((CHECKS + 1))
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))

    # Check scheduler is alive
    if ! kill -0 "$SCHED_PID" 2>/dev/null; then
        echo "❌ SCHEDULER CRASHED after ${ELAPSED}s ($CHECKS checks)"
        echo "FAILED with exit code 99"
        exit 99
    fi

    # Check scheduler is still attached
    CURRENT_OPS=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none")
    if [ "$CURRENT_OPS" != "mitosis" ]; then
        echo "❌ SCHEDULER DETACHED after ${ELAPSED}s (ops=$CURRENT_OPS)"
        echo "  sched_ext state: $(cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'unknown')"
        echo "FAILED with exit code 98"
        exit 98
    fi

    # Metrics
    CURRENT_CTXT=$(grep '^ctxt' /proc/stat | awk '{print $2}')
    CTXT_DELTA=$((CURRENT_CTXT - INITIAL_CTXT))
    CTXT_PER_SEC=$((CTXT_DELTA / (ELAPSED + 1)))
    LOADAVG=$(cat /proc/loadavg)

    echo "[${ELAPSED}s] check=$CHECKS OK | load=$LOADAVG | ctxt/s=$CTXT_PER_SEC"
done
