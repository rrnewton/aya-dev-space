#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER_BIN="$SCRIPT_DIR/../scx/scheds/rust_only/scx_simple/target/release/scx_simple"
echo "═══ SIMPLE STRESS COMBO ═══"
echo "Kernel: $(uname -r), CPUs: $(nproc)"
"$SCHEDULER_BIN" &
SCHED_PID=$!; sleep 3
echo "Scheduler: $(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo 'not attached')"
NCPU=$(nproc); HALF=$((NCPU/2)); [ "$HALF" -lt 2 ] && HALF=2
for i in $(seq $HALF); do while true; do :; done & done
(while true; do for i in $(seq 10); do /bin/true & done; wait; done) &
(while true; do dd if=/dev/urandom of=/dev/null bs=4k count=64 2>/dev/null; done) &
while kill -0 $SCHED_PID 2>/dev/null; do
    sleep 30; NOW=$(date +%s)
    OPS=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "NONE")
    LOAD=$(cat /proc/loadavg)
    echo "ops=$OPS load=$LOAD"
    [ "$OPS" != "simple" ] && { echo "❌ DETACHED"; exit 1; }
done
