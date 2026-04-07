#!/bin/bash
# Quick start: build and run the pure-Rust cosmos scheduler on this host.
# Requires: sudo, nightly Rust toolchain, kernel with sched_ext support.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSMOS_DIR="$SCRIPT_DIR/scx/scheds/rust_only/scx_cosmos"
DURATION="${1:-30}"

echo "=== Building scx_cosmos (pure Rust BPF scheduler) ==="
cd "$COSMOS_DIR"
cargo build --release 2>&1 | tail -5
echo ""

BINARY="$COSMOS_DIR/target/release/scx_cosmos_rs"
echo "Binary: $BINARY"
echo "Kernel: $(uname -r)"
echo "Duration: ${DURATION}s (pass seconds as first arg to change)"
echo ""

echo "=== Starting scheduler (sudo required) ==="
echo "Press Ctrl-C to detach early."
echo ""

sudo timeout "$DURATION" "$BINARY" "${@:2}" || {
    rc=$?
    if [ $rc -eq 124 ]; then
        echo ""
        echo "=== Scheduler ran for ${DURATION}s and exited cleanly ==="
    else
        echo ""
        echo "=== Scheduler exited with code $rc ==="
        echo ""
        echo "If you see 'invalid kernel function call', your kernel may be"
        echo "too old. The scheduler requires kernel 6.12+ with sched_ext."
        echo "Try: ./test_cosmos_vm.sh (runs in a VM with a compatible kernel)"
        exit $rc
    fi
}
