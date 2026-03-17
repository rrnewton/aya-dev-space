#!/bin/bash
#
# run-in-vm.sh — Run a BPF scheduler binary inside a virtme-ng VM.
#
# The VM boots the host kernel and shares the host filesystem, so the
# scheduler binary is accessible without copying.  The scheduler runs
# as root for the configured duration, then the VM shuts down cleanly.
#
# Usage:
#   ./testing/run-in-vm.sh <scheduler-binary> [duration-seconds]
#
# Examples:
#   ./testing/run-in-vm.sh ./scx/scheds/rust_only/scx_simple/target/release/scx_simple
#   ./testing/run-in-vm.sh ./scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos 30
#
# Topology (override via environment):
#   VNG_SMP     — QEMU -smp string (default: "16,sockets=2,cores=4,threads=2")
#   VNG_MEM     — guest memory (default: "2G")
#   VNG_NUMA    — set to "0" to disable NUMA (default: enabled, 2 nodes)
#   VNG_TOPOEXT — set to "0" to skip topoext workaround (default: enabled)
#   VERBOSE     — set to "1" for verbose output

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
SCHEDULER_BIN="${1:-}"
DURATION="${2:-20}"
VERBOSE="${VERBOSE:-0}"

if [[ -z "$SCHEDULER_BIN" ]]; then
    echo "Usage: $0 <scheduler-binary> [duration-seconds]" >&2
    exit 1
fi

# Resolve to absolute path so it works inside the VM (shared filesystem).
SCHEDULER_BIN="$(realpath "$SCHEDULER_BIN")"

if [[ ! -x "$SCHEDULER_BIN" ]]; then
    echo "ERROR: $SCHEDULER_BIN is not executable or does not exist" >&2
    exit 1
fi

if ! command -v virtme-run &>/dev/null; then
    echo "ERROR: virtme-run not found. Install with: pip install virtme-ng" >&2
    exit 1
fi

SCHED_NAME="$(basename "$SCHEDULER_BIN")"

# ---------------------------------------------------------------------------
# VM topology configuration
# ---------------------------------------------------------------------------
# Default: 2 NUMA nodes, 4 cores/node, 2 threads/core = 16 vCPUs
# This exercises NUMA awareness and SMT handling in schedulers.
#
# QEMU on AMD hosts needs "topoext" on the CPU to expose SMT topology.
# We handle this via a thin QEMU wrapper (see below).
VNG_SMP="${VNG_SMP:-16,sockets=2,cores=4,threads=2}"
VNG_MEM="${VNG_MEM:-2G}"
VNG_NUMA="${VNG_NUMA:-1}"
VNG_TOPOEXT="${VNG_TOPOEXT:-1}"

# Parse the total vCPU count from the SMP string for NUMA CPU split.
# Accepts either a bare number ("16") or a topology string ("16,sockets=2,...").
TOTAL_CPUS="${VNG_SMP%%,*}"
if ! [[ "$TOTAL_CPUS" =~ ^[0-9]+$ ]]; then
    echo "ERROR: VNG_SMP must start with a CPU count (got: $VNG_SMP)" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# QEMU wrapper for topoext (AMD SMT fix)
# ---------------------------------------------------------------------------
# QEMU with "-cpu host" on AMD hosts doesn't set the topoext CPUID bit,
# so the guest kernel can't detect SMT topology.  This wrapper intercepts
# the QEMU invocation and adds ",topoext=on" to the -cpu flag.
QEMU_WRAPPER_DIR=""
cleanup_wrapper() {
    [[ -n "$QEMU_WRAPPER_DIR" ]] && rm -rf "$QEMU_WRAPPER_DIR"
}

setup_qemu_wrapper() {
    QEMU_WRAPPER_DIR="$(mktemp -d /tmp/qemu-wrapper-XXXXXX)"
    cat > "$QEMU_WRAPPER_DIR/qemu-system-x86_64" << 'WRAPEOF'
#!/bin/bash
# Wrapper: add topoext=on to -cpu host for AMD SMT support
args=()
for arg in "$@"; do
    if [[ "$arg" == "host" ]] && [[ "${#args[@]}" -gt 0 ]] && [[ "${args[-1]}" == "-cpu" ]]; then
        args+=("host,topoext=on")
    else
        args+=("$arg")
    fi
done
exec /usr/bin/qemu-system-x86_64 "${args[@]}"
WRAPEOF
    chmod +x "$QEMU_WRAPPER_DIR/qemu-system-x86_64"
}

# ---------------------------------------------------------------------------
# Build virtme-run arguments
# ---------------------------------------------------------------------------
VIRTME_ARGS=(
    --kimg
    --mods auto
    --user root
    --cpus "$VNG_SMP"
    --memory "$VNG_MEM"
    --disable-microvm
)

# Add NUMA configuration: split CPUs evenly across 2 nodes.
if [[ "$VNG_NUMA" == "1" ]]; then
    HALF=$((TOTAL_CPUS / 2))
    MEM_HALF=$((${VNG_MEM%G} / 2))
    # Ensure we have at least 1G per node
    if [[ "$MEM_HALF" -lt 1 ]]; then
        MEM_HALF=1
    fi
    VIRTME_ARGS+=(
        --numa "${MEM_HALF}G,cpus=0-$((HALF - 1))"
        --numa "${MEM_HALF}G,cpus=${HALF}-$((TOTAL_CPUS - 1))"
    )
fi

if [[ "$VERBOSE" == "1" ]]; then
    VIRTME_ARGS+=(--verbose)
fi

# ---------------------------------------------------------------------------
# Build the in-VM command
# ---------------------------------------------------------------------------
# We run the scheduler under `timeout`.  timeout sends SIGTERM first, which
# lets the scheduler detach cleanly.  If it doesn't exit within 5 extra
# seconds, SIGKILL is sent.
#
# Exit-code conventions:
#   0   — scheduler exited on its own before the timeout (unusual but fine)
#   124 — timeout fired and killed the scheduler (normal / expected)
#   *   — scheduler crashed or failed to attach
VM_CMD="$(cat <<INNEREOF
echo ">>> VM booted, running $SCHED_NAME for ${DURATION}s ..."
timeout --signal=TERM --kill-after=5 "$DURATION" "$SCHEDULER_BIN" 2>&1
rc=\$?
if [ \$rc -eq 124 ]; then
    echo ">>> $SCHED_NAME ran for ${DURATION}s and was stopped by timeout (expected)"
    exit 0
elif [ \$rc -eq 0 ]; then
    echo ">>> $SCHED_NAME exited cleanly on its own"
    exit 0
else
    echo ">>> $SCHED_NAME FAILED with exit code \$rc"
    exit \$rc
fi
INNEREOF
)"

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
echo "=== run-in-vm: $SCHED_NAME (${DURATION}s) ==="
echo "    topology: $VNG_SMP, mem=$VNG_MEM, numa=$([ "$VNG_NUMA" = "1" ] && echo "2-node" || echo "off")"

# Set up QEMU wrapper for AMD topoext if requested.
EXTRA_PATH=""
if [[ "$VNG_TOPOEXT" == "1" ]]; then
    setup_qemu_wrapper
    EXTRA_PATH="$QEMU_WRAPPER_DIR:"
fi
trap 'cleanup_wrapper' EXIT

# virtme-run needs a valid PTY.  Wrap with `script` so it works from
# non-PTY contexts (CI, piped shells, etc.).
TMPLOG="$(mktemp /tmp/vng-run-XXXXXX.log)"
trap 'rm -f "$TMPLOG"; cleanup_wrapper' EXIT

# script(1) writes to both stdout and the logfile; redirect stdout to
# /dev/null so we only display the cleaned-up logfile afterwards.
script -qc "PATH=${EXTRA_PATH}\$PATH virtme-run ${VIRTME_ARGS[*]+"${VIRTME_ARGS[*]}"} --script-sh $(printf '%q' "$VM_CMD")" "$TMPLOG" >/dev/null 2>&1
VM_RC=$?

# Show the captured log (strip carriage returns and script header/footer).
grep -v '^Script ' "$TMPLOG" | tr -d '\r'

if [[ $VM_RC -ne 0 ]]; then
    echo "=== FAIL: $SCHED_NAME (vm exit code $VM_RC) ==="
    exit 1
fi

echo "=== PASS: $SCHED_NAME ==="
exit 0
