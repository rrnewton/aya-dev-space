#!/bin/bash
#
# run-all-tests.sh — Comprehensive test suite for all pure-Rust sched-ext schedulers.
#
# Runs topology variants, scheduler modes, and stress tests across
# mitosis, cosmos, and simple schedulers. Outputs a structured report.
#
# Usage:
#   ./testing/run-all-tests.sh [options]
#
# Options:
#   --quick           Quick mode: fewer topologies, 15s runs (default)
#   --extended        Extended mode: all topologies, 5min stress tests
#   --stress-only     Only run stress tests
#   --matrix-only     Only run topology matrix tests
#   --scheduler NAME  Only test the named scheduler (mitosis|cosmos|simple)
#   --skip-build      Don't build schedulers (use existing binaries)
#   --duration N      Override per-test duration (seconds)
#   --help            Show this help
#
# Environment:
#   VNG_KERNEL   — path to kernel image (default: 6.13.2 fbk7 kernel)
#   RESULTS_DIR  — directory for test logs (default: results/<timestamp>)

set -uo pipefail

# ── Paths ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_VM="$SCRIPT_DIR/run-in-vm.sh"
SCHEDS_DIR="$ROOT_DIR/scx/scheds/rust_only"

KERNEL="${VNG_KERNEL:-/boot/vmlinuz-6.13.2-0_fbk7_kdump_rc4_2_g299a07b1fe84}"

# ── Defaults ──────────────────────────────────────────────────────────

MODE="quick"
RUN_MATRIX=1
RUN_STRESS=1
SKIP_BUILD=0
DURATION=""
ONLY_SCHED=""
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results/$(date +%Y%m%d-%H%M%S)}"

# ── Parse args ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick)           MODE="quick"; shift ;;
        --extended)        MODE="extended"; shift ;;
        --stress-only)     RUN_MATRIX=0; shift ;;
        --matrix-only)     RUN_STRESS=0; shift ;;
        --scheduler)       ONLY_SCHED="$2"; shift 2 ;;
        --skip-build)      SKIP_BUILD=1; shift ;;
        --duration)        DURATION="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,/^$/s/^# \?//p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Mode-specific settings ───────────────────────────────────────────

if [[ "$MODE" == "quick" ]]; then
    MATRIX_DUR="${DURATION:-15}"
    STRESS_DUR="${DURATION:-30}"
else
    MATRIX_DUR="${DURATION:-20}"
    STRESS_DUR="${DURATION:-300}"
fi

# ── Scheduler definitions ────────────────────────────────────────────

declare -A SCHED_BIN
SCHED_BIN[mitosis]="$SCHEDS_DIR/scx_mitosis/target/release/scx_mitosis_rs"
SCHED_BIN[cosmos]="$SCHEDS_DIR/scx_cosmos/target/release/scx_cosmos_rs"
SCHED_BIN[simple]="$SCHEDS_DIR/scx_simple/target/release/scx_simple"

declare -A SCHED_DIR
SCHED_DIR[mitosis]="$SCHEDS_DIR/scx_mitosis"
SCHED_DIR[cosmos]="$SCHEDS_DIR/scx_cosmos"
SCHED_DIR[simple]="$SCHEDS_DIR/scx_simple"

declare -A SCHED_OPS_NAME
SCHED_OPS_NAME[mitosis]="mitosis"
SCHED_OPS_NAME[cosmos]="cosmos"
SCHED_OPS_NAME[simple]="simple"

# Which schedulers to test
if [[ -n "$ONLY_SCHED" ]]; then
    SCHEDULERS=("$ONLY_SCHED")
else
    SCHEDULERS=(mitosis cosmos simple)
fi

# ── Test results tracking ────────────────────────────────────────────

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
ALL_RESULTS=()

record_result() {
    local name="$1"
    local status="$2"  # PASS, FAIL, SKIP
    local detail="${3:-}"

    case "$status" in
        PASS) TOTAL_PASS=$((TOTAL_PASS + 1)); ALL_RESULTS+=("PASS  $name") ;;
        FAIL) TOTAL_FAIL=$((TOTAL_FAIL + 1)); ALL_RESULTS+=("FAIL  $name${detail:+  ($detail)}") ;;
        SKIP) TOTAL_SKIP=$((TOTAL_SKIP + 1)); ALL_RESULTS+=("SKIP  $name${detail:+  ($detail)}") ;;
    esac
}

# Check if a scheduler's build failed.
is_build_failed() {
    local sched="$1"
    local f
    for f in "${BUILD_FAILED[@]+"${BUILD_FAILED[@]}"}"; do
        [[ "$f" == "$sched" ]] && return 0
    done
    return 1
}

# ── Build ─────────────────────────────────────────────────────────────

build_scheduler() {
    local name="$1"
    local dir="${SCHED_DIR[$name]}"

    if [[ ! -d "$dir" ]]; then
        record_result "build/$name" SKIP "directory not found"
        return 1
    fi

    echo "  Building $name ..."
    if (cd "$dir" && cargo build --release 2>&1 | tail -3); then
        return 0
    else
        record_result "build/$name" FAIL "cargo build failed"
        return 1
    fi
}

# ── VM test runner ───────────────────────────────────────────────────

# Run a scheduler in a VM and check it attaches + survives.
#
# Args: test_name scheduler_name smp mem numa duration [extra_args...]
run_vm_test() {
    local test_name="$1"
    local sched="$2"
    local smp="$3"
    local mem="$4"
    local numa="$5"
    local dur="$6"
    shift 6
    local extra_args="$*"

    local bin="${SCHED_BIN[$sched]}"
    if [[ ! -x "$bin" ]]; then
        record_result "$test_name" SKIP "binary not found"
        return
    fi

    echo ""
    echo "--- $test_name ---"
    echo "    sched=$sched smp=$smp mem=$mem numa=$numa dur=${dur}s args='$extra_args'"

    local logfile="$RESULTS_DIR/${test_name//\//_}.log"

    # If extra args needed, create a wrapper script
    local actual_bin="$bin"
    local wrapper=""
    if [[ -n "$extra_args" ]]; then
        wrapper=$(mktemp /tmp/test-wrapper-XXXXXX.sh)
        cat > "$wrapper" <<WEOF
#!/bin/bash
exec "$bin" $extra_args
WEOF
        chmod +x "$wrapper"
        actual_bin="$wrapper"
    fi

    VNG_KERNEL="$KERNEL" VNG_SMP="$smp" VNG_MEM="$mem" VNG_NUMA="$numa" \
        "$RUN_VM" "$actual_bin" "$dur" > "$logfile" 2>&1
    local rc=$?

    rm -f "$wrapper"

    # Check results
    if [[ $rc -eq 0 ]] && ! grep -qE "FAILED|panic|BUG:|Oops" "$logfile"; then
        echo "    PASS"
        record_result "$test_name" PASS
    else
        echo "    FAIL (rc=$rc)"
        echo "    --- last 5 lines ---"
        tail -5 "$logfile" | sed 's/^/    /'
        echo "    --- full log: $logfile ---"
        record_result "$test_name" FAIL "rc=$rc"
    fi
}

# ── Stress test runner ───────────────────────────────────────────────

# Run a scheduler with stress workload.
#
# Args: test_name scheduler_name smp dur [extra_sched_args...]
run_stress_test() {
    local test_name="$1"
    local sched="$2"
    local smp="$3"
    local dur="$4"
    shift 4
    local extra_args="$*"

    local bin="${SCHED_BIN[$sched]}"
    if [[ ! -x "$bin" ]]; then
        record_result "$test_name" SKIP "binary not found"
        return
    fi

    echo ""
    echo "--- $test_name ---"
    echo "    sched=$sched smp=$smp dur=${dur}s stress=cpu+fork+pipe"

    local logfile="$RESULTS_DIR/${test_name//\//_}.log"

    # Build inner VM script: start scheduler, run stress, check survival
    local inner
    inner=$(mktemp /tmp/stress-inner-XXXXXX.sh)
    cat > "$inner" <<SEOF
#!/bin/bash
set -e
SCHED_BIN="$bin"
DUR=$dur
EXTRA="$extra_args"

echo ">>> Starting \$SCHED_BIN \$EXTRA ..."
\$SCHED_BIN \$EXTRA &
SCHED_PID=\$!
sleep 3

if ! kill -0 \$SCHED_PID 2>/dev/null; then
    echo ">>> FAILED: scheduler exited early"
    exit 1
fi

# Verify it attached
if [ -f /sys/kernel/sched_ext/root/ops ]; then
    ACTIVE=\$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null)
    echo ">>> Scheduler attached: \$ACTIVE"
fi

# Run stress (leave 10s margin)
STRESS_DUR=\$((DUR - 15))
[ \$STRESS_DUR -lt 5 ] && STRESS_DUR=5

echo ">>> Running stress for \${STRESS_DUR}s ..."
stress-ng --cpu 0 --timeout \${STRESS_DUR}s --metrics-brief 2>&1 &
P1=\$!
stress-ng --fork 2 --timeout \${STRESS_DUR}s --metrics-brief 2>&1 &
P2=\$!
stress-ng --pipe 2 --timeout \${STRESS_DUR}s --metrics-brief 2>&1 &
P3=\$!
wait \$P1 \$P2 \$P3 2>/dev/null || true
echo ">>> Stress completed"

# Check scheduler survived
if kill -0 \$SCHED_PID 2>/dev/null; then
    echo ">>> Scheduler survived stress: PASS"
else
    echo ">>> FAILED: scheduler died during stress"
    exit 1
fi

kill \$SCHED_PID 2>/dev/null
wait \$SCHED_PID 2>/dev/null || true
echo ">>> Scheduler stopped cleanly"
SEOF
    chmod +x "$inner"

    # Total VM duration = stress + margin
    local vm_dur=$((dur + 30))

    VNG_KERNEL="$KERNEL" VNG_SMP="$smp" VNG_MEM="4G" VNG_NUMA="1" \
        "$RUN_VM" "$inner" "$vm_dur" > "$logfile" 2>&1
    local rc=$?

    rm -f "$inner"

    if [[ $rc -eq 0 ]] && grep -q "Scheduler survived stress: PASS\|Scheduler stopped cleanly" "$logfile" \
       && ! grep -qE "FAILED|panic|BUG:|Oops" "$logfile"; then
        echo "    PASS"
        record_result "$test_name" PASS
    else
        echo "    FAIL (rc=$rc)"
        tail -5 "$logfile" | sed 's/^/    /'
        echo "    --- full log: $logfile ---"
        record_result "$test_name" FAIL "rc=$rc"
    fi
}

# ── Test matrix definitions ──────────────────────────────────────────
#
# Topologies:  "label:smp:mem:numa"
# Modes:       run_matrix_for_scheduler emits the (topo x mode) matrix

QUICK_TOPOS=(
    "1cpu:1:1G:0"
    "4cpu:4:1G:0"
    "8cpu:8,sockets=1,cores=4,threads=2:2G:0"
    "16cpu-numa:16,sockets=2,cores=4,threads=2:2G:1"
)

EXTENDED_TOPOS=(
    "${QUICK_TOPOS[@]}"
    "8cpu-no-smt:8,sockets=1,cores=8,threads=1:2G:0"
    "32cpu-4sock:32,sockets=4,cores=4,threads=2:4G:1"
)

# Run the topology x mode matrix for one scheduler.
run_matrix_for_scheduler() {
    local sched="$1"

    if [[ "$MODE" == "extended" ]]; then
        local topos=("${EXTENDED_TOPOS[@]}")
    else
        local topos=("${QUICK_TOPOS[@]}")
    fi

    # Define modes per scheduler. Each mode is "label|extra_args" (pipe-separated).
    local modes=()
    case "$sched" in
        mitosis)
            modes=(
                "default|"
                "llc|--enable-llc-awareness"
                "llc+ws|--enable-llc-awareness --enable-work-stealing"
                "no-cpu-ctrl|--cpu-controller-disabled"
            )
            ;;
        cosmos)
            modes=(
                "default|"
                "no-wake-sync|--no-wake-sync"
            )
            ;;
        simple)
            modes=(
                "default|"
            )
            ;;
        *)
            modes=("default|")
            ;;
    esac

    for topo_entry in "${topos[@]}"; do
        IFS=: read -r topo_label smp mem numa <<< "$topo_entry"

        for mode_entry in "${modes[@]}"; do
            local mode_label="${mode_entry%%|*}"
            local mode_args="${mode_entry#*|}"
            local test_name="matrix/${sched}/${topo_label}/${mode_label}"

            run_vm_test "$test_name" "$sched" "$smp" "$mem" "$numa" "$MATRIX_DUR" $mode_args
        done
    done
}

# ── Report printer ───────────────────────────────────────────────────

print_report() {
    echo ""
    echo "================================================================"
    echo "  TEST RESULTS"
    echo "================================================================"
    echo ""

    # Group and print by category
    local category
    for category in matrix stress build; do
        local found=0
        local r
        for r in "${ALL_RESULTS[@]+"${ALL_RESULTS[@]}"}"; do
            if [[ "$r" == *"$category/"* ]]; then
                if [[ $found -eq 0 ]]; then
                    echo "  -- ${category^^} --"
                    found=1
                fi
                local status="${r%%  *}"
                local name="${r#*  }"
                printf "    %-6s %s\n" "$status" "$name"
            fi
        done
        [[ $found -eq 1 ]] && echo ""
    done

    local total=$((TOTAL_PASS + TOTAL_FAIL + TOTAL_SKIP))
    echo "  Total: $total  Pass: $TOTAL_PASS  Fail: $TOTAL_FAIL  Skip: $TOTAL_SKIP"
    echo ""

    # Write machine-readable summary
    cat > "$RESULTS_DIR/summary.txt" <<EOF
date=$(date -Iseconds)
mode=$MODE
kernel=$KERNEL
total=$total
pass=$TOTAL_PASS
fail=$TOTAL_FAIL
skip=$TOTAL_SKIP
EOF

    local r
    for r in "${ALL_RESULTS[@]+"${ALL_RESULTS[@]}"}"; do
        echo "$r" >> "$RESULTS_DIR/summary.txt"
    done

    echo "  Logs:    $RESULTS_DIR/"
    echo "  Summary: $RESULTS_DIR/summary.txt"
    echo "================================================================"
}

# ══════════════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════════════

mkdir -p "$RESULTS_DIR"

echo "================================================================"
echo "  COMPREHENSIVE SCHEDULER TEST SUITE"
echo "================================================================"
echo "  Mode:       $MODE"
echo "  Kernel:     $KERNEL"
echo "  Matrix dur: ${MATRIX_DUR}s"
echo "  Stress dur: ${STRESS_DUR}s"
echo "  Schedulers: ${SCHEDULERS[*]}"
echo "  Results:    $RESULTS_DIR"
echo "  Tests:      $([ $RUN_MATRIX -eq 1 ] && echo "matrix ")$([ $RUN_STRESS -eq 1 ] && echo "stress")"
echo "================================================================"

if [[ ! -f "$KERNEL" ]]; then
    echo "ERROR: Kernel not found: $KERNEL" >&2
    exit 1
fi

if ! command -v virtme-run &>/dev/null; then
    echo "ERROR: virtme-run not found. Install: pip install virtme-ng" >&2
    exit 1
fi

# ── Build phase ──────────────────────────────────────────────────────

BUILD_FAILED=()

if [[ $SKIP_BUILD -eq 0 ]]; then
    echo ""
    echo "-- Building schedulers --"
    for sched in "${SCHEDULERS[@]}"; do
        if ! build_scheduler "$sched"; then
            BUILD_FAILED+=("$sched")
        fi
    done
fi

# ── Matrix tests (topology x mode) ──────────────────────────────────

if [[ $RUN_MATRIX -eq 1 ]]; then
    echo ""
    echo "-- Topology x Mode Matrix Tests --"

    for sched in "${SCHEDULERS[@]}"; do
        if is_build_failed "$sched"; then
            echo "  Skipping $sched (build failed)"
            continue
        fi
        run_matrix_for_scheduler "$sched"
    done
fi

# ── Stress tests ─────────────────────────────────────────────────────

if [[ $RUN_STRESS -eq 1 ]]; then
    echo ""
    echo "-- Stress Tests --"

    for sched in "${SCHEDULERS[@]}"; do
        if is_build_failed "$sched"; then
            echo "  Skipping $sched (build failed)"
            continue
        fi

        # Default stress test: 16 CPUs, NUMA
        run_stress_test \
            "stress/${sched}/16cpu-default" \
            "$sched" \
            "16,sockets=2,cores=4,threads=2" \
            "$STRESS_DUR"

        # Scheduler-specific stress modes
        if [[ "$sched" == "mitosis" ]]; then
            run_stress_test \
                "stress/mitosis/16cpu-llc" \
                mitosis \
                "16,sockets=2,cores=4,threads=2" \
                "$STRESS_DUR" \
                --enable-llc-awareness

            if [[ "$MODE" == "extended" ]]; then
                run_stress_test \
                    "stress/mitosis/16cpu-llc-ws" \
                    mitosis \
                    "16,sockets=2,cores=4,threads=2" \
                    "$STRESS_DUR" \
                    --enable-llc-awareness --enable-work-stealing

                run_stress_test \
                    "stress/mitosis/32cpu" \
                    mitosis \
                    "32,sockets=4,cores=4,threads=2" \
                    "$STRESS_DUR"
            fi
        fi
    done
fi

# ── Report ───────────────────────────────────────────────────────────

print_report

if [[ $TOTAL_FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
