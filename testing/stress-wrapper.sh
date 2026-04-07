#!/bin/bash
# stress-wrapper.sh — Runs stress-test.sh and saves output to shared filesystem.
# Usage: ./testing/stress-wrapper.sh [duration_seconds]

set -euo pipefail

DURATION="${1:-1800}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/../results/stress-test"
mkdir -p "$RESULTS_DIR"

OUTFILE="$RESULTS_DIR/run-$(date +%Y%m%d-%H%M%S).log"

echo "Output will be saved to: $OUTFILE"

SCHEDULER_BIN="$SCRIPT_DIR/../scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs"
export SCHEDULER_BIN

"$SCRIPT_DIR/stress-test.sh" "$DURATION" 2>&1 | tee "$OUTFILE"
RC=${PIPESTATUS[0]}

echo ""
echo "Results saved to: $OUTFILE"
exit "$RC"
