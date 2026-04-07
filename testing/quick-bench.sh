#!/bin/bash
set -euo pipefail

# Results go to /dev/kmsg so run-in-vm.sh captures them in dmesg
OUT="/tmp/bench-results.txt"
WC=4
WD=12

exec > "$OUT" 2>&1

echo "=== Scheduler Benchmark ==="
echo "Kernel: $(uname -r)"
echo "CPUs: $(nproc), Work: $WC CPUs x ${WD}s"
echo "Date: $(date -u)"
echo ""

run_stress() {
    stress-ng --cpu "$WC" --cpu-method matrixprod --timeout "${WD}s" --metrics-brief 2>&1
}

run_with_sched() {
    local name="$1"; shift
    echo "--- $name ---"
    "$@" >/dev/null 2>&1 &
    local pid=$!
    sleep 3
    local ops=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none")
    echo "  attached: $ops"
    if [ "$ops" != "none" ]; then
        run_stress | grep -i "matrixprod\|bogo"
    else
        echo "  FAILED to attach"
    fi
    kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
    sleep 1
    echo ""
}

echo "--- CFS baseline ---"
run_stress | grep -i "matrixprod\|bogo"
echo ""

S=$(find /home -name "scx_simple" -path "*/release/*" -type f 2>/dev/null | head -1)
C=$(find /home -name "scx_cosmos_rs" -path "*/release/*" -type f 2>/dev/null | head -1)
M=$(find /home -name "scx_mitosis_rs" -path "*/release/*" -type f 2>/dev/null | head -1)

[ -n "$S" ] && run_with_sched "scx_simple" "$S"
[ -n "$C" ] && run_with_sched "scx_cosmos" "$C"
[ -n "$M" ] && run_with_sched "MITOSIS" "$M"
[ -n "$M" ] && run_with_sched "MITOSIS+LLC" "$M" --enable-llc-awareness

echo "=== DONE ==="

# Print results so they appear in console output
exec 1>/dev/console 2>&1
cat "$OUT"
