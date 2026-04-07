#!/bin/bash
#
# test-mitosis-matrix.sh — Run scx_mitosis_rs across topology/config combinations.
#
# Usage: ./testing/test-mitosis-matrix.sh
#
# Generates a test matrix report to stdout.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_VM="$SCRIPT_DIR/run-in-vm.sh"
MITOSIS="$ROOT_DIR/scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs"
KERNEL="/boot/vmlinuz-6.13.2-0_fbk7_kdump_rc4_2_g299a07b1fe84"
DURATION="${1:-15}"

if [[ ! -x "$MITOSIS" ]]; then
    echo "ERROR: Build mitosis first: cd scx/scheds/rust_only/scx_mitosis && cargo build --release"
    exit 1
fi

if [[ ! -f "$KERNEL" ]]; then
    echo "ERROR: Kernel not found: $KERNEL"
    exit 1
fi

PASS=0
FAIL=0
SKIP=0
RESULTS=()

run_test() {
    local name="$1"
    local smp="$2"
    local mem="$3"
    local numa="$4"
    local extra_args="$5"
    local tmplog
    tmplog=$(mktemp /tmp/mitosis-test-XXXXXX.log)

    echo ""
    echo "━━━ TEST: $name ━━━"
    echo "    smp=$smp mem=$mem numa=$numa args='$extra_args'"

    # Create a wrapper script if we need extra args
    local bin="$MITOSIS"
    local wrapper=""
    if [[ -n "$extra_args" ]]; then
        wrapper=$(mktemp /tmp/mitosis-wrapper-XXXXXX.sh)
        cat > "$wrapper" <<WEOF
#!/bin/bash
exec "$MITOSIS" $extra_args
WEOF
        chmod +x "$wrapper"
        bin="$wrapper"
    fi

    VNG_KERNEL="$KERNEL" VNG_SMP="$smp" VNG_MEM="$mem" VNG_NUMA="$numa" \
        "$RUN_VM" "$bin" "$DURATION" > "$tmplog" 2>&1
    rc=$?

    # Show output
    cat "$tmplog"

    if [[ $rc -eq 0 ]] && ! grep -q "FAILED\|panic\|BUG\|Oops" "$tmplog"; then
        echo "    RESULT: ✅ PASS"
        PASS=$((PASS + 1))
        RESULTS+=("✅ PASS  $name")
    else
        echo "    RESULT: ❌ FAIL (rc=$rc)"
        FAIL=$((FAIL + 1))
        RESULTS+=("❌ FAIL  $name")
    fi

    rm -f "$tmplog" "$wrapper"
}

echo "═══════════════════════════════════════════════════════"
echo "  MITOSIS Test Matrix"
echo "  Kernel: $KERNEL"
echo "  Duration per test: ${DURATION}s"
echo "═══════════════════════════════════════════════════════"

# ── Test 1: Default (16 CPUs, 2 NUMA nodes) ────────────────────────
run_test "default-16cpu-numa" \
    "16,sockets=2,cores=4,threads=2" "2G" "1" ""

# ── Test 2: Single CPU ─────────────────────────────────────────────
run_test "single-cpu" \
    "1" "1G" "0" ""

# ── Test 3: 4 CPUs, no NUMA ────────────────────────────────────────
run_test "4cpu-no-numa" \
    "4" "1G" "0" ""

# ── Test 4: 32 CPUs, 4 sockets ────────────────────────────────────
run_test "32cpu-4sock" \
    "32,sockets=4,cores=4,threads=2" "4G" "1" ""

# ── Test 5: LLC awareness enabled ─────────────────────────────────
run_test "16cpu-llc-aware" \
    "16,sockets=2,cores=4,threads=2" "2G" "1" "--enable-llc-awareness"

# ── Test 6: LLC awareness + work stealing ─────────────────────────
run_test "16cpu-llc-ws" \
    "16,sockets=2,cores=4,threads=2" "2G" "1" "--enable-llc-awareness --enable-work-stealing"

# ── Test 7: 8 CPUs, no SMT, no NUMA ──────────────────────────────
run_test "8cpu-no-smt-no-numa" \
    "8,sockets=1,cores=8,threads=1" "2G" "0" ""

# ── Test 8: cpu_controller_disabled ────────────────────────────────
run_test "16cpu-no-cpu-ctrl" \
    "16,sockets=2,cores=4,threads=2" "2G" "1" "--cpu-controller-disabled"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  RESULTS SUMMARY"
echo "═══════════════════════════════════════════════════════"
echo ""
for r in "${RESULTS[@]}"; do
    echo "  $r"
done
echo ""
echo "  Total: $((PASS + FAIL)) tests — $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════════════"
