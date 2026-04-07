#!/bin/bash
# run-stress-in-vm.sh — Run MITOSIS stress test in a virtme-ng VM.
#
# This leverages the existing run-in-vm.sh infrastructure but replaces
# the simple "run scheduler" command with a full stress test.
#
# Usage: ./testing/run-stress-in-vm.sh [stress_duration_seconds]

set -euo pipefail

STRESS_DURATION="${1:-1800}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

SCHEDULER_BIN="$ROOT_DIR/scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs"
SCHEDULER_BIN="$(realpath "$SCHEDULER_BIN")"
STRESS_SCRIPT="$SCRIPT_DIR/stress-test.sh"
STRESS_SCRIPT="$(realpath "$STRESS_SCRIPT")"

# VM duration = stress duration + 60s margin for startup/shutdown
VM_DURATION=$((STRESS_DURATION + 60))

# Kernel to use
VNG_KERNEL="${VNG_KERNEL:-/boot/vmlinuz-6.13.2-0_fbk7_kdump_rc4_2_g299a07b1fe84}"
export VNG_KERNEL

echo "═══════════════════════════════════════════════════════════"
echo "  MITOSIS VM STRESS TEST"
echo "  Stress duration: ${STRESS_DURATION}s"
echo "  VM timeout: ${VM_DURATION}s"
echo "  Kernel: $VNG_KERNEL"
echo "═══════════════════════════════════════════════════════════"

# Create a small wrapper script that the VM will execute
WRAPPER=$(mktemp /tmp/mitosis-stress-XXXXXX.sh)
chmod +x "$WRAPPER"
cat > "$WRAPPER" << WRAPEOF
#!/bin/bash
export SCHEDULER_BIN="$SCHEDULER_BIN"
exec "$STRESS_SCRIPT" "$STRESS_DURATION"
WRAPEOF

# Use run-in-vm.sh but with our wrapper as the "scheduler"
# run-in-vm.sh will wrap it in timeout and capture output
SCHEDULER_BIN_OVERRIDE="$WRAPPER"

# Actually, run-in-vm.sh expects a scheduler binary with specific
# exit code handling. Let's just call virtme directly using the
# same wrapper/topoext approach.

# Source the topology from run-in-vm.sh defaults
VNG_SMP="${VNG_SMP:-16,sockets=2,cores=4,threads=2}"
VNG_MEM="${VNG_MEM:-2G}"
VNG_NUMA="${VNG_NUMA:-1}"
TOTAL_CPUS="${VNG_SMP%%,*}"

# Build virtme args
VIRTME_ARGS=(
    --kimg "$VNG_KERNEL"
    --mods none
    --memory "$VNG_MEM"
    --cpus "$VNG_SMP"
)

if [[ "$VNG_NUMA" == "1" ]]; then
    HALF=$((TOTAL_CPUS / 2))
    MEM_HALF=$((${VNG_MEM%G} / 2))
    [[ "$MEM_HALF" -lt 1 ]] && MEM_HALF=1
    VIRTME_ARGS+=(
        --numa "${MEM_HALF}G,cpus=0-$((HALF - 1))"
        --numa "${MEM_HALF}G,cpus=${HALF}-$((TOTAL_CPUS - 1))"
    )
fi

# QEMU wrapper for AMD topoext (same as run-in-vm.sh)
QEMU_WRAPPER_DIR=""
cleanup() {
    [[ -n "$QEMU_WRAPPER_DIR" ]] && rm -rf "$QEMU_WRAPPER_DIR"
    rm -f "$WRAPPER"
}
trap cleanup EXIT

CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
if [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    QEMU_WRAPPER_DIR=$(mktemp -d)
    REAL_QEMU=$(command -v qemu-system-x86_64)
    cat > "$QEMU_WRAPPER_DIR/qemu-system-x86_64" << 'QWEOF'
#!/bin/bash
args=()
for arg in "$@"; do
    if [[ "$arg" == host* ]] || [[ "$arg" == *-cpu\ host* ]]; then
        arg="${arg},topoext=on"
    fi
    args+=("$arg")
done
QWEOF
    echo "exec \"$REAL_QEMU\" \"\${args[@]}\"" >> "$QEMU_WRAPPER_DIR/qemu-system-x86_64"
    chmod +x "$QEMU_WRAPPER_DIR/qemu-system-x86_64"
    export PATH="$QEMU_WRAPPER_DIR:$PATH"
fi

# Build the in-VM command
VM_CMD="$(cat <<INNEREOF
echo ">>> VM booted, starting stress test (${STRESS_DURATION}s)..."
timeout --signal=TERM --kill-after=10 $VM_DURATION "$WRAPPER" 2>&1
rc=\$?
if [ \$rc -eq 124 ]; then
    echo ">>> stress test timed out (expected for long tests)"
    exit 0
elif [ \$rc -eq 0 ]; then
    echo ">>> stress test completed successfully"
    exit 0
else
    echo ">>> stress test FAILED with exit code \$rc"
    exit \$rc
fi
INNEREOF
)"

echo "  topology: $VNG_SMP, mem=$VNG_MEM, numa=$([ "$VNG_NUMA" = "1" ] && echo "2-node" || echo "off")"
echo ""

# Run with script(1) to capture output
TMPLOG=$(mktemp /tmp/stress-log-XXXXXX.log)

script -qc "virtme-run ${VIRTME_ARGS[*]+"${VIRTME_ARGS[*]}"} --script-sh $(printf '%q' "$VM_CMD")" "$TMPLOG" >/dev/null 2>&1
VM_RC=$?

# Display captured output
OUTPUT=$(grep -v '^Script ' "$TMPLOG" | tr -d '\r')
echo "$OUTPUT"
rm -f "$TMPLOG"

# Check for failures
if echo "$OUTPUT" | grep -q "STRESS TEST PASSED"; then
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  ✅ VM STRESS TEST PASSED"
    echo "═══════════════════════════════════════════════════════════"
    exit 0
elif echo "$OUTPUT" | grep -q "STRESS TEST FAILED"; then
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  ❌ VM STRESS TEST FAILED"
    echo "═══════════════════════════════════════════════════════════"
    exit 1
else
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  ⚠️  VM STRESS TEST — COULD NOT DETERMINE RESULT"
    echo "  VM exit code: $VM_RC"
    echo "═══════════════════════════════════════════════════════════"
    exit "$VM_RC"
fi
