#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER_BIN="$SCRIPT_DIR/../scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs"
echo "═══ MITOSIS LLC-AWARE STRESS ═══"
echo "Kernel: $(uname -r), CPUs: $(nproc)"
"$SCHEDULER_BIN" --enable-llc-awareness &
SCHED_PID=$!; sleep 3
echo "Scheduler: $(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo 'not attached')"
# Stress
NCPU=$(nproc); HALF=$((NCPU/2)); [ "$HALF" -lt 2 ] && HALF=2
for i in $(seq $HALF); do while true; do :; done & done
(while true; do for i in $(seq 10); do /bin/true & done; wait; done) &
(while true; do dd if=/dev/urandom of=/dev/null bs=4k count=64 2>/dev/null; done) &
START=$(date +%s)
while kill -0 $SCHED_PID 2>/dev/null; do
    sleep 30; NOW=$(date +%s); ELAPSED=$((NOW-START))
    OPS=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "NONE")
    LOAD=$(cat /proc/loadavg)
    echo "[${ELAPSED}s] ops=$OPS load=$LOAD"
    [ "$OPS" != "mitosis" ] && { echo "❌ DETACHED"; exit 1; }
done
