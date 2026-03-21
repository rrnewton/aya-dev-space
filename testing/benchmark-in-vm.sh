#!/bin/bash
#
# benchmark-in-vm.sh — Run benchmarks inside a virtme-ng VM for isolation.
#
# This wraps benchmark.sh to run inside a VM using the same infrastructure
# as test-all-schedulers.sh / run-in-vm.sh.  This provides:
#   - Consistent CPU topology (configurable via VNG_SMP)
#   - NUMA simulation
#   - Isolation from host system load
#   - Reproducible results across runs
#
# Usage:
#   ./testing/benchmark-in-vm.sh <scheduler-binary> [results-label]
#
# Example — compare both cosmos variants:
#   # Build both
#   (cd scx/scheds/rust/scx_cosmos && cargo build --release)
#   (cd scx/scheds/rust_only/scx_cosmos && cargo build --release)
#
#   # Benchmark both in VMs with identical topology
#   ./testing/benchmark-in-vm.sh \
#       scx/scheds/rust/scx_cosmos/target/release/scx_cosmos \
#       standard-cosmos
#
#   ./testing/benchmark-in-vm.sh \
#       scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos \
#       purerust-cosmos
#
#   # Compare
#   ./testing/compare-results.sh results/standard-cosmos results/purerust-cosmos
#
# Environment (same as run-in-vm.sh):
#   VNG_SMP        — VM CPU topology (default: "16,sockets=2,cores=4,threads=2")
#   VNG_MEM        — VM memory (default: "4G", needs enough for benchmarks)
#   VNG_NUMA       — "0" to disable NUMA (default: enabled)
#   VNG_KERNEL     — path to a vmlinuz image (default: host kernel)
#   BENCH_ITERATIONS — iterations per benchmark (default: 3)
#   BENCH_SKIP     — comma-separated benchmarks to skip

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCHEDULER_BIN="${1:-}"
RESULTS_LABEL="${2:-$(date +%Y%m%d-%H%M%S)}"

if [[ -z "$SCHEDULER_BIN" ]]; then
    echo "Usage: $0 <scheduler-binary> [results-label]" >&2
    exit 1
fi

SCHEDULER_BIN="$(realpath "$SCHEDULER_BIN")"

if [[ ! -x "$SCHEDULER_BIN" ]]; then
    echo "ERROR: $SCHEDULER_BIN is not executable" >&2
    exit 1
fi

# VM config — more memory for benchmarks.
export VNG_SMP="${VNG_SMP:-16,sockets=2,cores=4,threads=2}"
export VNG_MEM="${VNG_MEM:-4G}"
export VNG_NUMA="${VNG_NUMA:-1}"
export VNG_TOPOEXT="${VNG_TOPOEXT:-1}"
export VNG_KERNEL="${VNG_KERNEL:-}"

BENCH_ITERATIONS="${BENCH_ITERATIONS:-3}"
BENCH_SKIP="${BENCH_SKIP:-kernel-compile}"

RESULTS_DIR="$REPO_ROOT/results/$RESULTS_LABEL"

echo "================================================================"
echo " VM Benchmark Runner"
echo " Scheduler: $(basename "$SCHEDULER_BIN")"
echo " Topology:  $VNG_SMP"
echo " Memory:    $VNG_MEM"
echo " Results:   $RESULTS_DIR"
echo "================================================================"

if ! command -v virtme-run &>/dev/null; then
    echo "ERROR: virtme-run not found. Install: pip install virtme-ng" >&2
    exit 1
fi

# Build the in-VM command that:
# 1. Installs benchmark tools (if not present)
# 2. Runs the benchmark script
VM_CMD="$(cat <<INNEREOF
echo ">>> VM booted, starting benchmarks..."

# The benchmark script, scheduler binary, and host tools are all
# accessible via the shared filesystem.
export BENCH_ITERATIONS=$BENCH_ITERATIONS
export BENCH_SKIP="$BENCH_SKIP"
export SCHED_ARGS="${SCHED_ARGS:-}"

# Run the benchmark suite.
$SCRIPT_DIR/benchmark.sh "$SCHEDULER_BIN" "$RESULTS_DIR"
rc=\$?

echo ">>> Benchmarks complete (exit code \$rc)"
exit \$rc
INNEREOF
)"

# Build virtme-run arguments (same pattern as run-in-vm.sh).
VIRTME_ARGS=(
    --mods auto
    --user root
    --cpus "$VNG_SMP"
    --memory "$VNG_MEM"
    --disable-microvm
)

if [[ -n "$VNG_KERNEL" ]]; then
    VIRTME_ARGS+=(--kimg "$VNG_KERNEL")
else
    VIRTME_ARGS+=(--kimg)
fi

# NUMA config.
TOTAL_CPUS="${VNG_SMP%%,*}"
if [[ "$VNG_NUMA" == "1" ]]; then
    HALF=$((TOTAL_CPUS / 2))
    MEM_HALF=$((${VNG_MEM%G} / 2))
    [[ "$MEM_HALF" -lt 1 ]] && MEM_HALF=1
    VIRTME_ARGS+=(
        --numa "${MEM_HALF}G,cpus=0-$((HALF - 1))"
        --numa "${MEM_HALF}G,cpus=${HALF}-$((TOTAL_CPUS - 1))"
    )
fi

# QEMU topoext wrapper (same as run-in-vm.sh).
QEMU_WRAPPER_DIR=""
cleanup_wrapper() {
    [[ -n "$QEMU_WRAPPER_DIR" ]] && rm -rf "$QEMU_WRAPPER_DIR"
}

if [[ "$VNG_TOPOEXT" == "1" ]]; then
    QEMU_WRAPPER_DIR="$(mktemp -d /tmp/qemu-wrapper-XXXXXX)"
    cat > "$QEMU_WRAPPER_DIR/qemu-system-x86_64" << 'WRAPEOF'
#!/bin/bash
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
fi
trap 'cleanup_wrapper' EXIT

EXTRA_PATH=""
[[ -n "$QEMU_WRAPPER_DIR" ]] && EXTRA_PATH="$QEMU_WRAPPER_DIR:"

# Run the VM.
echo ""
echo "--- Launching VM ---"

TMPLOG="$(mktemp /tmp/vng-bench-XXXXXX.log)"
trap 'rm -f "$TMPLOG"; cleanup_wrapper' EXIT

script -qc "PATH=${EXTRA_PATH}\$PATH virtme-run ${VIRTME_ARGS[*]+"${VIRTME_ARGS[*]}"} --script-sh $(printf '%q' "$VM_CMD")" "$TMPLOG" >/dev/null 2>&1
VM_RC=$?

grep -v '^Script ' "$TMPLOG" | tr -d '\r'

if [[ $VM_RC -ne 0 ]]; then
    echo "=== VM benchmark FAILED (exit code $VM_RC) ==="
    exit 1
fi

echo ""
echo "=== VM benchmark complete ==="
echo "Results in: $RESULTS_DIR"

if [[ -f "$RESULTS_DIR/summary.json" ]]; then
    echo ""
    echo "=== Summary ==="
    cat "$RESULTS_DIR/summary.json"
fi
