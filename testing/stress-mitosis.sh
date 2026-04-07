#!/bin/bash
#
# stress-mitosis.sh — Run scx_mitosis_rs with a stress workload inside a VM.
#
# Attaches the scheduler then runs CPU, fork, I/O, and memory stress
# in parallel for the configured duration.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MITOSIS="$ROOT_DIR/scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs"
KERNEL="/boot/vmlinuz-6.13.2-0_fbk7_kdump_rc4_2_g299a07b1fe84"
DURATION="${1:-120}"
SMP="${2:-16,sockets=2,cores=4,threads=2}"
EXTRA_ARGS="${3:-}"

echo "═══ MITOSIS Stress Test ═══"
echo "  Duration: ${DURATION}s"
echo "  Topology: $SMP"
echo "  Extra args: ${EXTRA_ARGS:-none}"

# Create combined script that runs mitosis + stress in parallel
STRESS_CMD=$(cat <<'INNEREOF'
DURATION_ARG="$1"
MITOSIS_BIN="$2"
EXTRA="$3"

echo ">>> Starting scheduler..."
$MITOSIS_BIN $EXTRA &
SCHED_PID=$!
sleep 3

# Verify it attached
if ! cat /sys/kernel/sched_ext/root/ops 2>/dev/null | grep -q mitosis; then
    echo ">>> FAILED: scheduler did not attach"
    kill $SCHED_PID 2>/dev/null
    exit 1
fi
echo ">>> Scheduler attached: $(cat /sys/kernel/sched_ext/root/ops)"

# Calculate stress duration (leave 10s for shutdown)
STRESS_DUR=$((DURATION_ARG - 15))
if [ $STRESS_DUR -lt 5 ]; then
    STRESS_DUR=5
fi

echo ">>> Running stress for ${STRESS_DUR}s..."

# CPU stress (all CPUs)
stress-ng --cpu 0 --timeout ${STRESS_DUR}s --metrics-brief 2>&1 &
PID_CPU=$!

# Fork stress (rapid process creation/destruction)
stress-ng --fork 4 --timeout ${STRESS_DUR}s --metrics-brief 2>&1 &
PID_FORK=$!

# I/O stress (disk I/O generates scheduler pressure)
stress-ng --io 2 --timeout ${STRESS_DUR}s --metrics-brief 2>&1 &
PID_IO=$!

# Memory stress (allocation churn)
stress-ng --vm 2 --vm-bytes 64M --timeout ${STRESS_DUR}s --metrics-brief 2>&1 &
PID_MEM=$!

# Pipe stress (IPC, context switches)
stress-ng --pipe 4 --timeout ${STRESS_DUR}s --metrics-brief 2>&1 &
PID_PIPE=$!

# Wait for stress to finish
wait $PID_CPU $PID_FORK $PID_IO $PID_MEM $PID_PIPE 2>/dev/null
echo ">>> Stress workloads completed"

# Check scheduler is still attached
if cat /sys/kernel/sched_ext/root/ops 2>/dev/null | grep -q mitosis; then
    echo ">>> Scheduler still attached after stress: PASS"
else
    echo ">>> FAILED: scheduler detached during stress"
    exit 1
fi

# Graceful shutdown
kill $SCHED_PID 2>/dev/null
wait $SCHED_PID 2>/dev/null
echo ">>> Scheduler stopped cleanly"
INNEREOF
)

# Write the inner script to a temp file
INNER_SCRIPT=$(mktemp /tmp/mitosis-stress-inner-XXXXXX.sh)
echo "#!/bin/bash" > "$INNER_SCRIPT"
echo "$STRESS_CMD" >> "$INNER_SCRIPT"
chmod +x "$INNER_SCRIPT"

# Write outer wrapper that calls inner with args
WRAPPER=$(mktemp /tmp/mitosis-stress-wrapper-XXXXXX.sh)
cat > "$WRAPPER" <<WEOF
#!/bin/bash
exec $INNER_SCRIPT $DURATION $MITOSIS "$EXTRA_ARGS"
WEOF
chmod +x "$WRAPPER"

VNG_KERNEL="$KERNEL" VNG_SMP="$SMP" VNG_MEM="4G" VNG_NUMA="1" \
    "$SCRIPT_DIR/run-in-vm.sh" "$WRAPPER" "$DURATION"
RC=$?

rm -f "$INNER_SCRIPT" "$WRAPPER"
exit $RC
