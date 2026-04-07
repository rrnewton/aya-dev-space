#!/bin/bash
set -euo pipefail
#
# test-scheduler.sh — Boot a kernel in virtme-ng, load a scheduler, run a
# workload, and check for crashes.
#
# Usage:
#   ./test-scheduler.sh <kernel-bzImage> <scheduler-binary> [workload-seconds]
#
# Environment:
#   VNG_RW        — mount root filesystem read-write (default: true)
#   SCHBENCH_BIN  — path to schbench binary (default: schbench on PATH)

KERNEL="${1:?Usage: $0 <bzImage> <scheduler-binary> [seconds]}"
SCHED_PATH="${2:?Usage: $0 <bzImage> <scheduler-binary> [seconds]}"
WORKLOAD_SECS="${3:-30}"

GUEST_TIMEOUT=$((WORKLOAD_SECS + 60))
SCHED_NAME="$(basename "$SCHED_PATH")"
SCHBENCH_BIN="${SCHBENCH_BIN:-schbench}"

if [[ ! -f "$KERNEL" ]]; then
    echo "ERROR: kernel image not found: $KERNEL" >&2
    exit 1
fi
if [[ ! -x "$SCHED_PATH" ]]; then
    echo "ERROR: scheduler binary not found or not executable: $SCHED_PATH" >&2
    exit 1
fi
if ! command -v vng &>/dev/null; then
    echo "ERROR: vng (virtme-ng) not found" >&2
    exit 1
fi

echo "=== test-scheduler: $SCHED_NAME on $(basename "$KERNEL") ==="
echo "    workload: schbench for ${WORKLOAD_SECS}s"

# Build in-VM script: start scheduler in background, run workload, stop scheduler
VM_SCRIPT="$(cat <<INNEREOF
set -e
echo ">>> Booting, loading $SCHED_NAME ..."

# Start scheduler in background
$SCHED_PATH -v &
SCHED_PID=\$!
sleep 3

# Verify scheduler attached
if ! kill -0 \$SCHED_PID 2>/dev/null; then
    echo ">>> FAILED: $SCHED_NAME exited early"
    exit 1
fi
echo ">>> $SCHED_NAME attached (pid \$SCHED_PID)"

# Run workload if schbench is available
if command -v $SCHBENCH_BIN &>/dev/null; then
    echo ">>> Running schbench for ${WORKLOAD_SECS}s ..."
    timeout --foreground ${WORKLOAD_SECS} $SCHBENCH_BIN -m 2 -t 4 -r ${WORKLOAD_SECS} 2>&1 || true
else
    echo ">>> schbench not found, running stress workload instead ..."
    timeout --foreground ${WORKLOAD_SECS} stress-ng --cpu \$(nproc) --timeout ${WORKLOAD_SECS}s 2>&1 || true
fi

# Stop scheduler
echo ">>> Stopping $SCHED_NAME ..."
kill \$SCHED_PID 2>/dev/null || true
wait \$SCHED_PID 2>/dev/null || true

# Check dmesg for problems
echo ">>> Checking dmesg for errors ..."
dmesg > /tmp/dmesg.log
if grep -qiE 'BUG:|WARNING:|panic|KASAN|UBSAN|general protection fault' /tmp/dmesg.log; then
    echo ">>> KERNEL ERRORS DETECTED:"
    grep -iE 'BUG:|WARNING:|panic|KASAN|UBSAN|general protection fault' /tmp/dmesg.log
    echo ">>> FAILED: kernel errors found"
    exit 1
fi

echo ">>> PASSED: $SCHED_NAME ran successfully"
INNEREOF
)"

rm -f /tmp/test-sched-output
timeout --preserve-status ${GUEST_TIMEOUT} \
    vng --user root -m 4G --cpu 8 --rw -v -r "$KERNEL" -- \
        "$VM_SCRIPT" \
        2> >(tee /tmp/test-sched-output) </dev/null

# Check output for failures
if grep -q "FAILED" /tmp/test-sched-output 2>/dev/null; then
    echo "=== FAIL: $SCHED_NAME ==="
    cp /tmp/test-sched-output test-scheduler.ci.log 2>/dev/null || true
    exit 1
fi

# Filter known-harmless messages and check for kernel issues
if grep -v \
    -e "Speculative Return Stack Overflow" \
    -e "RETBleed:" \
    /tmp/test-sched-output 2>/dev/null | \
    grep -qiE '\bBUG:\b|\bWARNING:\b|\berror\b.*sched|\bpanic\b'; then
    echo "=== FAIL: $SCHED_NAME (kernel errors in output) ==="
    cp /tmp/test-sched-output test-scheduler.ci.log 2>/dev/null || true
    exit 1
fi

cp /tmp/test-sched-output test-scheduler.ci.log 2>/dev/null || true
echo "=== PASS: $SCHED_NAME ==="
exit 0
