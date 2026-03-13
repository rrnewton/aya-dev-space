#!/bin/bash
#
# test-all-schedulers.sh — Build and test all pure-Rust sched-ext schedulers.
#
# Builds each scheduler in release mode, then runs it inside a VNG VM
# for a configurable duration.  Prints a pass/fail summary at the end.
#
# Usage:
#   ./testing/test-all-schedulers.sh [duration-seconds]
#
# Environment:
#   SKIP_BUILD=1   — skip the cargo build step (use existing binaries)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DURATION="${1:-20}"
SKIP_BUILD="${SKIP_BUILD:-0}"

# ---------------------------------------------------------------------------
# Schedulers to test
# ---------------------------------------------------------------------------
SCHEDS_DIR="$REPO_ROOT/scx/scheds/rust_only"
SCHEDULERS=(
    "scx_simple"
    "scx_cosmos"
)

declare -A RESULTS

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build_scheduler() {
    local name="$1"
    local dir="$SCHEDS_DIR/$name"

    if [[ ! -d "$dir" ]]; then
        echo "WARNING: $dir does not exist, skipping" >&2
        RESULTS["$name"]="SKIP (not found)"
        return 1
    fi

    echo "--- Building $name (release) ---"
    if (cd "$dir" && cargo build --release 2>&1); then
        echo "--- $name built OK ---"
        return 0
    else
        echo "--- $name BUILD FAILED ---"
        RESULTS["$name"]="FAIL (build)"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test
# ---------------------------------------------------------------------------
test_scheduler() {
    local name="$1"
    local binary="$SCHEDS_DIR/$name/target/release/$name"

    if [[ ! -x "$binary" ]]; then
        echo "WARNING: $binary not found or not executable" >&2
        RESULTS["$name"]="FAIL (no binary)"
        return
    fi

    echo ""
    echo "============================================"
    echo " Testing: $name (${DURATION}s)"
    echo "============================================"

    if "$SCRIPT_DIR/run-in-vm.sh" "$binary" "$DURATION"; then
        RESULTS["$name"]="PASS"
    else
        RESULTS["$name"]="FAIL"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "======================================================="
echo " sched-ext Pure-Rust Scheduler Test Suite"
echo " Kernel: $(uname -r)"
echo " Duration per scheduler: ${DURATION}s"
echo "======================================================="
echo ""

# Build phase
if [[ "$SKIP_BUILD" != "1" ]]; then
    for sched in "${SCHEDULERS[@]}"; do
        build_scheduler "$sched" || true
    done
    echo ""
else
    echo "(skipping build phase — SKIP_BUILD=1)"
    echo ""
fi

# Test phase
for sched in "${SCHEDULERS[@]}"; do
    # Skip if already marked as failed during build
    if [[ -n "${RESULTS[$sched]:-}" ]]; then
        echo "Skipping $sched (${RESULTS[$sched]})"
        continue
    fi
    test_scheduler "$sched"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "======================================================="
echo " RESULTS"
echo "======================================================="

PASS=0
FAIL=0
SKIP=0

for sched in "${SCHEDULERS[@]}"; do
    result="${RESULTS[$sched]:-UNKNOWN}"
    printf "  %-20s %s\n" "$sched" "$result"
    case "$result" in
        PASS)     ((PASS++)) ;;
        SKIP*)    ((SKIP++)) ;;
        *)        ((FAIL++)) ;;
    esac
done

echo ""
echo "  Total: ${#SCHEDULERS[@]}  Pass: $PASS  Fail: $FAIL  Skip: $SKIP"
echo "======================================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
