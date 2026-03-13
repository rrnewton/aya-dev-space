#!/bin/bash
#
# run-in-vm.sh — Run a BPF scheduler binary inside a VNG (virtme-ng) VM.
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

if ! command -v vng &>/dev/null; then
    echo "ERROR: vng (virtme-ng) not found. Install with: pip install virtme-ng" >&2
    exit 1
fi

SCHED_NAME="$(basename "$SCHEDULER_BIN")"

# ---------------------------------------------------------------------------
# VNG options
# ---------------------------------------------------------------------------
VNG_ARGS=()
if [[ "$VERBOSE" == "1" ]]; then
    VNG_ARGS+=("--verbose")
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

# VNG requires a valid PTY.  Wrap with `script` so it works from non-PTY
# contexts (CI, piped shells, etc.).
TMPLOG="$(mktemp /tmp/vng-run-XXXXXX.log)"
trap 'rm -f "$TMPLOG"' EXIT

# script(1) writes to both stdout and the logfile; redirect stdout to
# /dev/null so we only display the cleaned-up logfile afterwards.
script -qc "vng ${VNG_ARGS[*]+"${VNG_ARGS[*]}"} --run -- bash -c $(printf '%q' "$VM_CMD")" "$TMPLOG" >/dev/null 2>&1
VNG_RC=$?

# Show the captured log (strip carriage returns and script header/footer).
grep -v '^Script ' "$TMPLOG" | tr -d '\r'

if [[ $VNG_RC -ne 0 ]]; then
    echo "=== FAIL: $SCHED_NAME (vng exit code $VNG_RC) ==="
    exit 1
fi

echo "=== PASS: $SCHED_NAME ==="
exit 0
