#!/bin/bash
# stress-advanced.sh — Advanced stress tests for scx_mitosis
#
# Tests: attach/detach cycling, fork bomb resistance, memory pressure,
# mixed concurrent workloads. Runs INSIDE a virtme-ng VM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER_BIN="${SCHEDULER_BIN:-$SCRIPT_DIR/../scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs}"
SCHEDULER_BIN="$(realpath "$SCHEDULER_BIN")"
PASS=0
FAIL=0
TOTAL=0

result() {
    TOTAL=$((TOTAL + 1))
    if [ "$1" -eq 0 ]; then
        PASS=$((PASS + 1))
        echo "  ✅ $2"
    else
        FAIL=$((FAIL + 1))
        echo "  ❌ $2"
    fi
}

check_attached() {
    [ -f /sys/kernel/sched_ext/root/ops ] && \
    [ "$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null)" = "mitosis" ]
}

echo "═══════════════════════════════════════════════════════════"
echo "  MITOSIS ADVANCED STRESS TESTS"
echo "  $(date)  Kernel: $(uname -r)  CPUs: $(nproc)"
echo "═══════════════════════════════════════════════════════════"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "── TEST 1: Attach/Detach Cycling (10 cycles × 5s) ──"
# Verifies scheduler can attach, run briefly, detach cleanly, repeat.
CYCLES=10
CYCLE_OK=0
for i in $(seq $CYCLES); do
    "$SCHEDULER_BIN" &
    PID=$!
    sleep 3
    if check_attached; then
        sleep 2
        kill $PID 2>/dev/null
        wait $PID 2>/dev/null || true
        sleep 1
        # Verify clean detach
        if ! check_attached; then
            CYCLE_OK=$((CYCLE_OK + 1))
        fi
    else
        kill $PID 2>/dev/null; wait $PID 2>/dev/null || true
    fi
done
result $( [ $CYCLE_OK -eq $CYCLES ] && echo 0 || echo 1 ) \
    "Attach/detach cycling: $CYCLE_OK/$CYCLES clean cycles"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "── TEST 2: Fork Bomb Resistance ──"
# Start scheduler, then create 200 processes rapidly. Scheduler must survive.
"$SCHEDULER_BIN" &
SCHED_PID=$!
sleep 3

if check_attached; then
    # Controlled fork bomb: 200 short-lived processes
    for batch in $(seq 20); do
        for j in $(seq 10); do
            /bin/true &
        done
        wait
    done
    sleep 2

    if check_attached && kill -0 $SCHED_PID 2>/dev/null; then
        result 0 "Fork bomb resistance: 200 processes, scheduler survived"
    else
        result 1 "Fork bomb resistance: scheduler died or detached"
    fi
else
    result 1 "Fork bomb resistance: scheduler failed to attach"
fi
kill $SCHED_PID 2>/dev/null; wait $SCHED_PID 2>/dev/null || true
sleep 1

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "── TEST 3: Heavy Fork Stress (1000 processes) ──"
"$SCHEDULER_BIN" &
SCHED_PID=$!
sleep 3

if check_attached; then
    START=$(date +%s)
    for batch in $(seq 100); do
        for j in $(seq 10); do
            /bin/true &
        done
        wait
    done
    END=$(date +%s)
    ELAPSED=$((END - START))

    if check_attached && kill -0 $SCHED_PID 2>/dev/null; then
        result 0 "Heavy fork stress: 1000 processes in ${ELAPSED}s, scheduler OK"
    else
        result 1 "Heavy fork stress: scheduler died after 1000 forks"
    fi
else
    result 1 "Heavy fork stress: scheduler failed to attach"
fi
kill $SCHED_PID 2>/dev/null; wait $SCHED_PID 2>/dev/null || true
sleep 1

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "── TEST 4: Memory Pressure ──"
"$SCHEDULER_BIN" &
SCHED_PID=$!
sleep 3

if check_attached; then
    # Allocate and touch memory aggressively
    if command -v stress-ng &>/dev/null; then
        stress-ng --vm 2 --vm-bytes 128M --vm-method all --timeout 20s 2>&1 | tail -3 &
        STRESS_PID=$!
    else
        # Fallback: manual memory pressure
        (for i in $(seq 5); do head -c 64M /dev/urandom > /dev/null; done) &
        STRESS_PID=$!
    fi
    wait $STRESS_PID 2>/dev/null || true

    if check_attached && kill -0 $SCHED_PID 2>/dev/null; then
        result 0 "Memory pressure: 256MB stress, scheduler OK"
    else
        result 1 "Memory pressure: scheduler died"
    fi
else
    result 1 "Memory pressure: scheduler failed to attach"
fi
kill $SCHED_PID 2>/dev/null; wait $SCHED_PID 2>/dev/null || true
sleep 1

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "── TEST 5: Mixed Concurrent Workloads (30s) ──"
"$SCHEDULER_BIN" &
SCHED_PID=$!
sleep 3

if check_attached; then
    NCPU=$(nproc)
    HALF=$((NCPU / 2)); [ "$HALF" -lt 2 ] && HALF=2

    # CPU spinners
    for i in $(seq $HALF); do
        (timeout 25 bash -c 'while true; do :; done') &
    done

    # Fork stress
    (timeout 25 bash -c 'while true; do for i in $(seq 5); do /bin/true & done; wait; done') &

    # I/O stress
    (timeout 25 bash -c 'while true; do dd if=/dev/urandom of=/dev/null bs=4k count=64 2>/dev/null; done') &

    # Memory churn
    (timeout 25 bash -c 'while true; do head -c 16M /dev/urandom > /dev/null; done') &

    # Monitor
    for tick in $(seq 6); do
        sleep 5
        if ! check_attached || ! kill -0 $SCHED_PID 2>/dev/null; then
            result 1 "Mixed workloads: scheduler died at ${tick}×5s"
            break
        fi
        LOAD=$(cat /proc/loadavg | cut -d' ' -f1-3)
        echo "    [${tick}×5s] load=$LOAD attached=yes"
    done

    # Kill remaining background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
    wait 2>/dev/null || true

    if check_attached && kill -0 $SCHED_PID 2>/dev/null; then
        result 0 "Mixed workloads: 30s all-stressor concurrent test passed"
    fi
else
    result 1 "Mixed workloads: scheduler failed to attach"
fi
kill $SCHED_PID 2>/dev/null; wait $SCHED_PID 2>/dev/null || true
sleep 1

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "── TEST 6: Rapid Task Creation/Destruction ──"
"$SCHEDULER_BIN" &
SCHED_PID=$!
sleep 3

if check_attached; then
    START=$(date +%s)
    # Create 50 processes that each create 10 children
    for batch in $(seq 50); do
        (for j in $(seq 10); do /bin/true & done; wait) &
    done
    wait
    END=$(date +%s)
    ELAPSED=$((END - START))

    if check_attached && kill -0 $SCHED_PID 2>/dev/null; then
        result 0 "Rapid task creation: 500 nested tasks in ${ELAPSED}s"
    else
        result 1 "Rapid task creation: scheduler died"
    fi
else
    result 1 "Rapid task creation: scheduler failed to attach"
fi
kill $SCHED_PID 2>/dev/null; wait $SCHED_PID 2>/dev/null || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  RESULTS: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════════════════════════"

if [ $FAIL -gt 0 ]; then
    echo "  FAILED"
    exit 1
fi
echo "  ALL TESTS PASSED"
