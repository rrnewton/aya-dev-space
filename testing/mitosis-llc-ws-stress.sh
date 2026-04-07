#!/bin/bash
# mitosis-llc-ws-stress.sh — LLC-aware + work stealing stress test
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER_BIN="$SCRIPT_DIR/../scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs"

echo "═══ MITOSIS LLC+WS EXTENDED STRESS ═══"
echo "Kernel: $(uname -r), CPUs: $(nproc)"

"$SCHEDULER_BIN" --enable-llc-awareness --enable-work-stealing &
SCHED_PID=$!
sleep 3

OPS=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "none")
echo "Scheduler: $OPS"

if [ "$OPS" != "mitosis" ]; then
    echo "FAILED: scheduler not attached"
    exit 1
fi

NCPU=$(nproc); HALF=$((NCPU/2)); [ "$HALF" -lt 2 ] && HALF=2
INITIAL_CTXT=$(grep '^ctxt' /proc/stat | awk '{print $2}')
START=$(date +%s)

# Mixed workload: CPU + fork + IO
for i in $(seq $HALF); do while true; do :; done & done
(while true; do for i in $(seq 10); do /bin/true & done; wait; done) &
(while true; do dd if=/dev/urandom of=/dev/null bs=4k count=64 2>/dev/null; done) &
(while true; do head -c 16M /dev/urandom > /dev/null; done) &

echo "Stress running..."
while kill -0 $SCHED_PID 2>/dev/null; do
    sleep 30
    NOW=$(date +%s); ELAPSED=$((NOW-START))
    OPS=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "NONE")
    LOAD=$(cat /proc/loadavg)
    CTXT=$(grep '^ctxt' /proc/stat | awk '{print $2}')
    RATE=$(( (CTXT - INITIAL_CTXT) / (ELAPSED + 1) ))
    echo "[${ELAPSED}s] ops=$OPS load=$LOAD ctxt/s=$RATE"
    if [ "$OPS" != "mitosis" ]; then
        echo "FAILED: scheduler detached at ${ELAPSED}s"
        exit 1
    fi
done
