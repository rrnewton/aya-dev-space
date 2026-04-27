#!/bin/bash
#
# sweep-vm.sh — Run benchmark sweep inside a virtme-ng VM
#
# This runs the same benchmarks as sweep.sh but inside a VM with
# configurable kernel and topology. Useful for testing on different
# kernels (e.g., 6.16) without rebooting the host.
#
# Usage: ./testing/sweep-vm.sh <results-base-dir> [kernel-image]
#
# Environment:
#   VNG_SMP     — QEMU topology (default: "16,sockets=2,cores=4,threads=2")
#   VNG_MEM     — guest memory (default: "4G")
#   BENCH_ITERATIONS — iterations per benchmark (default: 3)
#
set -euo pipefail

RESULTS_BASE="${1:?Usage: sweep-vm.sh <results-base-dir> [kernel-image]}"
KERNEL_IMG="${2:-/boot/vmlinuz-6.16.0}"

VNG_SMP="${VNG_SMP:-16,sockets=2,cores=4,threads=2}"
VNG_MEM="${VNG_MEM:-4G}"
VNG_NUMA="${VNG_NUMA:-1}"
VNG_TOPOEXT="${VNG_TOPOEXT:-1}"
ITERATIONS="${BENCH_ITERATIONS:-3}"

C_COSMOS="$(realpath scx/target/release/scx_cosmos)"
RUST_COSMOS="$(realpath scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos)"

echo "=== VM Benchmark Sweep ==="
echo "Kernel: $KERNEL_IMG"
echo "Topology: $VNG_SMP, mem=$VNG_MEM"
echo "Iterations: $ITERATIONS"
echo ""

# Resolve total CPUs from SMP string
TOTAL_CPUS="${VNG_SMP%%,*}"

# ---------------------------------------------------------------------------
# Build the in-VM benchmark script (self-contained, runs inside the VM)
# ---------------------------------------------------------------------------
VM_BENCH_SCRIPT="$(mktemp /tmp/vm-bench-XXXXXX.sh)"
chmod +x "$VM_BENCH_SCRIPT"

cat > "$VM_BENCH_SCRIPT" << 'VMEOF'
#!/bin/bash
set -euo pipefail

RESULTS_BASE="$1"
C_COSMOS="$2"
RUST_COSMOS="$3"
ITERATIONS="$4"

SCHBENCH_GROUPS_SMALL=4
SCHBENCH_GROUPS_LARGE=16
SCHBENCH_DURATION=10
STRESS_WORKERS=4
STRESS_CPU_WORKERS=8
STRESS_DURATION=10
SETTLE=3
WARMUP=5

KERNEL=$(uname -r)
CPUS=$(nproc)

echo "=== VM Guest Benchmark ==="
echo "Kernel: $KERNEL"
echo "CPUs: $CPUS"
echo ""

median() {
    local sorted=($(printf '%s\n' "$@" | sort -g))
    local n=${#sorted[@]}
    echo "${sorted[$((n/2))]}"
}

extract_schbench_p99_wakeup() {
    grep -A1 "Wakeup Latencies" "$1" | grep "99.0th" | tail -1 | awk '{print $2}'
}
extract_schbench_p99_request() {
    grep -A5 "Request Latencies" "$1" | grep "99.0th" | tail -1 | awk '{print $2}'
}
extract_schbench_rps() {
    grep "average rps" "$1" | tail -1 | awk '{print $3}'
}
extract_stressng_ops() {
    grep -E "metrc.*$1" "$2" | tail -1 | awk '{print $7}'
}

run_suite() {
    local label="$1" dir="$2"
    mkdir -p "$dir/raw"

    echo ""
    echo "======== $label ========"

    local wakeup_4=() request_4=() rps_4=()
    local wakeup_16=() request_16=() rps_16=()
    local ctx_ops=() pipe_ops=() cpu_ops=()

    for i in $(seq 1 "$ITERATIONS"); do
        echo "  iteration $i/$ITERATIONS"

        schbench -m $SCHBENCH_GROUPS_SMALL -r $SCHBENCH_DURATION > "$dir/raw/schbench-4-$i.txt" 2>&1
        wakeup_4+=($(extract_schbench_p99_wakeup "$dir/raw/schbench-4-$i.txt"))
        request_4+=($(extract_schbench_p99_request "$dir/raw/schbench-4-$i.txt"))
        rps_4+=($(extract_schbench_rps "$dir/raw/schbench-4-$i.txt"))
        sleep $SETTLE

        schbench -m $SCHBENCH_GROUPS_LARGE -r $SCHBENCH_DURATION > "$dir/raw/schbench-16-$i.txt" 2>&1
        wakeup_16+=($(extract_schbench_p99_wakeup "$dir/raw/schbench-16-$i.txt"))
        request_16+=($(extract_schbench_p99_request "$dir/raw/schbench-16-$i.txt"))
        rps_16+=($(extract_schbench_rps "$dir/raw/schbench-16-$i.txt"))
        sleep $SETTLE

        stress-ng --context $STRESS_WORKERS -t $STRESS_DURATION --metrics-brief > "$dir/raw/context-$i.txt" 2>&1
        ctx_ops+=($(extract_stressng_ops context "$dir/raw/context-$i.txt"))
        sleep $SETTLE

        stress-ng --pipe $STRESS_WORKERS -t $STRESS_DURATION --metrics-brief > "$dir/raw/pipe-$i.txt" 2>&1
        pipe_ops+=($(extract_stressng_ops pipe "$dir/raw/pipe-$i.txt"))
        sleep $SETTLE

        stress-ng --cpu $STRESS_CPU_WORKERS -t $STRESS_DURATION --metrics-brief > "$dir/raw/cpu-$i.txt" 2>&1
        cpu_ops+=($(extract_stressng_ops cpu "$dir/raw/cpu-$i.txt"))
        sleep $SETTLE
    done

    local m_wakeup_4=$(median "${wakeup_4[@]}")
    local m_request_4=$(median "${request_4[@]}")
    local m_rps_4=$(median "${rps_4[@]}")
    local m_wakeup_16=$(median "${wakeup_16[@]}")
    local m_request_16=$(median "${request_16[@]}")
    local m_rps_16=$(median "${rps_16[@]}")
    local m_ctx=$(median "${ctx_ops[@]}")
    local m_pipe=$(median "${pipe_ops[@]}")
    local m_cpu=$(median "${cpu_ops[@]}")

    cat > "$dir/summary.json" <<JEOF
{
  "label": "$label",
  "kernel": "$KERNEL",
  "cpus": $CPUS,
  "iterations": $ITERATIONS,
  "schbench_4grp": { "wakeup_p99_us": $m_wakeup_4, "request_p99_us": $m_request_4, "avg_rps": $m_rps_4 },
  "schbench_16grp": { "wakeup_p99_us": $m_wakeup_16, "request_p99_us": $m_request_16, "avg_rps": $m_rps_16 },
  "context_switch": { "ops_per_sec": $m_ctx },
  "pipe": { "ops_per_sec": $m_pipe },
  "cpu": { "bogo_ops_per_sec": $m_cpu }
}
JEOF

    echo ""
    echo "  Results:"
    printf "    %-30s %s\n" "schbench 4grp wakeup p99:" "${m_wakeup_4} us"
    printf "    %-30s %s\n" "schbench 4grp request p99:" "${m_request_4} us"
    printf "    %-30s %s\n" "schbench 4grp avg RPS:" "${m_rps_4}"
    printf "    %-30s %s\n" "schbench 16grp wakeup p99:" "${m_wakeup_16} us"
    printf "    %-30s %s\n" "schbench 16grp request p99:" "${m_request_16} us"
    printf "    %-30s %s\n" "schbench 16grp avg RPS:" "${m_rps_16}"
    printf "    %-30s %s\n" "context switch ops/sec:" "${m_ctx}"
    printf "    %-30s %s\n" "pipe ops/sec:" "${m_pipe}"
    printf "    %-30s %s\n" "cpu bogo ops/sec:" "${m_cpu}"
}

# --- EEVDF ---
pkill -f scx_cosmos 2>/dev/null || true
sleep 2
run_suite "EEVDF (built-in)" "$RESULTS_BASE/eevdf"

# --- C Cosmos ---
echo ">>> Starting C Cosmos..."
"$C_COSMOS" &
SCHED_PID=$!
sleep $WARMUP
if ! kill -0 "$SCHED_PID" 2>/dev/null; then
    echo "ERROR: C Cosmos failed to start"
    wait "$SCHED_PID" 2>/dev/null || true
    # Continue without C cosmos results
    echo "SKIPPED" > "$RESULTS_BASE/c-cosmos-skipped.txt"
else
    run_suite "C Cosmos" "$RESULTS_BASE/c-cosmos"
    kill "$SCHED_PID" 2>/dev/null || true
    wait "$SCHED_PID" 2>/dev/null || true
    sleep 3
fi

# --- Rust Cosmos ---
echo ">>> Starting Rust Cosmos..."
"$RUST_COSMOS" &
SCHED_PID=$!
sleep $WARMUP
if ! kill -0 "$SCHED_PID" 2>/dev/null; then
    echo "ERROR: Rust Cosmos failed to start (expected on 6.16 without CO-RE)"
    wait "$SCHED_PID" 2>/dev/null || true
    echo "SKIPPED (verifier rejection, needs CO-RE)" > "$RESULTS_BASE/rust-cosmos-skipped.txt"
else
    run_suite "Rust Cosmos" "$RESULTS_BASE/rust-cosmos"
    kill "$SCHED_PID" 2>/dev/null || true
    wait "$SCHED_PID" 2>/dev/null || true
    sleep 3
fi

echo ""
echo "=== VM Sweep Complete ==="
VMEOF

# ---------------------------------------------------------------------------
# Build virtme-run arguments
# ---------------------------------------------------------------------------
VIRTME_ARGS=(
    --mods auto
    --user root
    --cpus "$VNG_SMP"
    --memory "$VNG_MEM"
    --disable-microvm
    --rw
)

if [[ -f "$KERNEL_IMG" ]]; then
    VIRTME_ARGS+=(--kimg "$KERNEL_IMG")
else
    echo "ERROR: Kernel image $KERNEL_IMG not found" >&2
    exit 1
fi

# NUMA configuration
HALF=$((TOTAL_CPUS / 2))
MEM_MB=$((${VNG_MEM%G} * 1024))
MEM_HALF_MB=$((MEM_MB / 2))
if [[ "$VNG_NUMA" == "1" ]]; then
    MEM_HALF=$((${VNG_MEM%G} / 2))
    [[ "$MEM_HALF" -lt 1 ]] && MEM_HALF=1
    VIRTME_ARGS+=(
        --numa "${MEM_HALF}G,cpus=0-$((HALF - 1))"
        --numa "${MEM_HALF}G,cpus=${HALF}-$((TOTAL_CPUS - 1))"
    )
fi

# QEMU wrapper for AMD topoext
QEMU_WRAPPER_DIR=""
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
trap '[[ -n "$QEMU_WRAPPER_DIR" ]] && rm -rf "$QEMU_WRAPPER_DIR"; rm -f "$VM_BENCH_SCRIPT"' EXIT

mkdir -p "$RESULTS_BASE"

# Build the guest command
GUEST_CMD="bash $VM_BENCH_SCRIPT $RESULTS_BASE $C_COSMOS $RUST_COSMOS $ITERATIONS"

echo "Starting VM..."
TMPLOG="$(mktemp /tmp/vm-sweep-XXXXXX.log)"

if [[ -n "$QEMU_WRAPPER_DIR" ]]; then
    PATH="$QEMU_WRAPPER_DIR:$PATH" script -q -c "virtme-run ${VIRTME_ARGS[*]} --script-sh '$GUEST_CMD'" "$TMPLOG"
else
    script -q -c "virtme-run ${VIRTME_ARGS[*]} --script-sh '$GUEST_CMD'" "$TMPLOG"
fi

echo ""
echo "VM sweep complete. Results in $RESULTS_BASE/"
rm -f "$TMPLOG"
