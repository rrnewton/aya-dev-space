#!/bin/bash
# cosmos-stress-combo.sh — scx_cosmos with same stress workload as mitosis test
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER_BIN="$SCRIPT_DIR/../scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos_rs"

echo "═══ COSMOS STRESS COMBO ═══"
echo "Kernel: $(uname -r), CPUs: $(nproc)"

"$SCHEDULER_BIN" &
SCHED_PID=$!; sleep 3

echo "Scheduler: $(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo 'not attached')"

NCPU=$(nproc); HALF=$((NCPU/2)); [ "$HALF" -lt 2 ] && HALF=2
INITIAL_CTXT=$(grep '^ctxt' /proc/stat | awk '{print $2}')
START=$(date +%s)

# Same stress as mitosis tests
for i in $(seq $HALF); do while true; do :; done & done
(while true; do for i in $(seq 10); do /bin/true & done; wait; done) &
(while true; do dd if=/dev/urandom of=/dev/null bs=4k count=64 2>/dev/null; done) &
(while true; do head -c 16M /dev/urandom > /dev/null; done) &

while kill -0 $SCHED_PID 2>/dev/null; do
    sleep 30; NOW=$(date +%s); ELAPSED=$((NOW-START))
    OPS=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "NONE")
    LOAD=$(cat /proc/loadavg)
    CTXT=$(grep '^ctxt' /proc/stat | awk '{print $2}')
    DELTA=$((CTXT - INITIAL_CTXT))
    RATE=$((DELTA / (ELAPSED + 1)))
    echo "[${ELAPSED}s] ops=$OPS load=$LOAD ctxt/s=$RATE"
    [ "$OPS" != "cosmos" ] && { echo "❌ DETACHED"; exit 1; }
done
