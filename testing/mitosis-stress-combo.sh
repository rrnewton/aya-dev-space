#!/bin/bash
# mitosis-stress-combo.sh — Stress test MITOSIS in 3 modes
# Designed for run-in-vm.sh: runs scheduler + stress, verifies it survives.
set -euo pipefail

echo "=== MITOSIS Stress Combo ==="
echo "Kernel: $(uname -r)"
echo "CPUs: $(nproc)"
echo ""

MITOSIS=$(find /home -name "scx_mitosis_rs" -path "*/release/*" -type f 2>/dev/null | head -1)
if [ -z "$MITOSIS" ]; then
    echo "FAILED: scx_mitosis_rs not found"
    exit 1
fi

test_mode() {
    local name="$1"
    shift
    echo "--- $name ---"
    $MITOSIS "$@" >/dev/null 2>&1 &
    local pid=$!
    sleep 3

    local ops=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none")
    if [ "$ops" = "none" ]; then
        echo "  FAILED: scheduler did not attach"
        kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
        exit 1
    fi
    echo "  attached: $ops"

    # CPU stress
    stress-ng --cpu 4 --cpu-method matrixprod --timeout 8s >/dev/null 2>&1
    echo "  cpu-stress: OK"

    # Fork storm
    stress-ng --fork 2 --timeout 5s >/dev/null 2>&1
    echo "  fork-storm: OK"

    # Context switch stress
    stress-ng --pipe 4 --timeout 5s >/dev/null 2>&1
    echo "  pipe-ctx-switch: OK"

    # Verify still attached
    ops=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none")
    if [ "$ops" = "none" ]; then
        echo "  FAILED: scheduler detached during stress!"
        kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
        exit 1
    fi
    echo "  still attached: $ops"

    kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
    sleep 2
    echo "  PASS"
    echo ""
}

test_mode "default (no flags)"
test_mode "LLC-aware" --enable-llc-awareness
test_mode "LLC-aware + work-stealing" --enable-llc-awareness --enable-work-stealing

echo "=== ALL 3 MODES PASSED ==="
# Keep alive for timeout to kill us cleanly
sleep 999
