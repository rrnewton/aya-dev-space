#!/bin/bash
# Quick start: build and run the pure-Rust cosmos scheduler in a VM.
# Requires: virtme-ng (vng), a 6.12+ kernel image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSMOS_DIR="$SCRIPT_DIR/scx/scheds/rust_only/scx_cosmos"
DURATION="${1:-30}"

# Find a suitable kernel image (6.12+)
KERNEL=""
for k in /boot/vmlinuz-6.1[3-9]* /boot/vmlinuz-6.[2-9]* /boot/vmlinuz-7.*; do
    [ -f "$k" ] && KERNEL="$k" && break
done

if [ -z "$KERNEL" ]; then
    echo "ERROR: No kernel 6.12+ found in /boot/"
    echo "The cosmos scheduler requires sched_ext support (kernel 6.12+)."
    echo ""
    echo "Available kernels:"
    ls /boot/vmlinuz-* 2>/dev/null || echo "  (none)"
    exit 1
fi

# Check for vng
if ! command -v vng &>/dev/null; then
    echo "ERROR: virtme-ng (vng) not found."
    echo "Install: pip install virtme-ng"
    exit 1
fi

echo "=== Building scx_cosmos (pure Rust BPF scheduler) ==="
cd "$COSMOS_DIR"
cargo build --release 2>&1 | tail -5
echo ""

BINARY="$COSMOS_DIR/target/release/scx_cosmos"
echo "Binary:   $BINARY"
echo "VM kernel: $KERNEL"
echo "Duration:  ${DURATION}s"
echo ""

echo "=== Launching VM ==="
cd "$SCRIPT_DIR"

vng -r "$KERNEL" -- bash -c "
    echo '=== VM booted ==='
    echo \"Kernel: \$(uname -r)\"
    echo \"CPUs:   \$(nproc)\"
    echo ''
    echo '=== Starting cosmos scheduler ==='
    timeout $DURATION $BINARY ${*:2} 2>&1
    rc=\$?
    echo ''
    if [ \$rc -eq 124 ]; then
        echo '=== Scheduler ran for ${DURATION}s and exited cleanly ==='
    elif [ \$rc -eq 0 ]; then
        echo '=== Scheduler exited cleanly ==='
    else
        echo \"=== Scheduler exited with code \$rc ===\"
    fi
"
