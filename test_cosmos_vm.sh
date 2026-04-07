#!/bin/bash
# Quick start: build and run the pure-Rust cosmos scheduler in a VM.
# Delegates to testing/run-in-vm.sh for VM management.
# Requires: virtme-ng (vng), a 6.12+ kernel image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COSMOS_DIR="$SCRIPT_DIR/scx/scheds/rust_only/scx_cosmos"
DURATION="${1:-30}"

# Find binary (handles both scx_cosmos and scx_cosmos_rs names)
BINARY=""
for name in scx_cosmos_rs scx_cosmos; do
    [ -f "$COSMOS_DIR/target/release/$name" ] && BINARY="$COSMOS_DIR/target/release/$name" && break
done

if [ -z "$BINARY" ]; then
    echo "=== Building scx_cosmos (pure Rust BPF scheduler) ==="
    cd "$COSMOS_DIR"
    cargo build --release 2>&1 | tail -5
    cd "$SCRIPT_DIR"
    for name in scx_cosmos_rs scx_cosmos; do
        [ -f "$COSMOS_DIR/target/release/$name" ] && BINARY="$COSMOS_DIR/target/release/$name" && break
    done
    if [ -z "$BINARY" ]; then
        echo "ERROR: build succeeded but binary not found" >&2
        exit 1
    fi
fi

echo "Binary: $BINARY"
echo ""

# Delegate to run-in-vm.sh which handles:
# - NUMA topology configuration
# - script(1) PTY wrapping for output capture
# - pass/fail detection from log
#
# Find a 6.12+ kernel for the VM (cosmos requires sched_ext)
for k in /boot/vmlinuz-6.1[3-9]* /boot/vmlinuz-6.[2-9]* /boot/vmlinuz-7.*; do
    [ -f "$k" ] && export VNG_KERNEL="$k" && break
done
if [ -z "${VNG_KERNEL:-}" ]; then
    echo "ERROR: No kernel 6.12+ found in /boot/"
    echo "Available kernels:"
    ls /boot/vmlinuz-* 2>/dev/null || echo "  (none)"
    exit 1
fi

exec "$SCRIPT_DIR/testing/run-in-vm.sh" "$BINARY" "$DURATION"
