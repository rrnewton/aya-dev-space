#!/bin/bash
#
# run-matrix.sh — Scheduler × Kernel × Topology test matrix
#
# Discovers available kernels and schedulers, runs every combination,
# outputs a summary table. Designed for local development and CI.
#
# Usage:
#   ./testing/run-matrix.sh                              # full sweep
#   ./testing/run-matrix.sh --kernels 6.13 --stress      # filtered + stress
#   ./testing/run-matrix.sh --json > results.json        # CI mode
#   ./testing/run-matrix.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_IN_VM="$SCRIPT_DIR/run-in-vm.sh"
STRESS_COMBO="$SCRIPT_DIR/mitosis-stress-combo.sh"

# ── Defaults ─────────────────────────────────────────────────────────
FILTER_KERNELS=""
FILTER_SCHEDULERS=""
TOPOLOGIES="4,8"
TIMEOUT=10
STRESS=false
RETRIES=1
JSON=false
HELP=false

# ── Color ────────────────────────────────────────────────────────────
if [[ -t 1 ]] && [[ -z "${CI:-}" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    GREEN=$'\033[32m'
    RED=$'\033[31m'
    YELLOW=$'\033[33m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    GREEN="" RED="" YELLOW="" BOLD="" RESET=""
fi

# ── Parse args ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernels)    FILTER_KERNELS="$2"; shift 2 ;;
        --schedulers) FILTER_SCHEDULERS="$2"; shift 2 ;;
        --topologies) TOPOLOGIES="$2"; shift 2 ;;
        --timeout)    TIMEOUT="$2"; shift 2 ;;
        --stress)     STRESS=true; shift ;;
        --retries)    RETRIES="$2"; shift 2 ;;
        --json)       JSON=true; shift ;;
        --help|-h)    HELP=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if $HELP; then
    cat <<'USAGE'
run-matrix.sh — Scheduler × Kernel × Topology test matrix

OPTIONS:
  --kernels "6.13,6.16"    Filter kernels by version substring
  --schedulers "simple"    Filter schedulers by name substring
  --topologies "4,8,32"    CPU counts to test (default: 4,8)
  --timeout 10             Seconds per test (default: 10)
  --stress                 Also run mitosis stress combo tests
  --retries 3              Retry flaky tests N times (default: 1)
  --json                   Output JSON results (for CI)
  --help                   Show this help

EXAMPLES:
  ./testing/run-matrix.sh
  ./testing/run-matrix.sh --kernels 6.13 --stress
  ./testing/run-matrix.sh --json > results.json
  ./testing/run-matrix.sh --topologies "4,8,16,32" --retries 3
USAGE
    exit 0
fi

# ── Discover kernels ─────────────────────────────────────────────────
discover_kernels() {
    local kernels=()
    for k in /boot/vmlinuz-*; do
        [[ -f "$k" ]] || continue
        # Skip kdump/rescue kernels
        [[ "$k" == *rescue* ]] && continue
        # Extract version
        local ver="${k#/boot/vmlinuz-}"
        # Apply filter
        if [[ -n "$FILTER_KERNELS" ]]; then
            local match=false
            IFS=',' read -ra filters <<< "$FILTER_KERNELS"
            for f in "${filters[@]}"; do
                if [[ "$ver" == *"$f"* ]]; then
                    match=true
                    break
                fi
            done
            $match || continue
        fi
        # Check if kernel has sched_ext — skip if config explicitly says no.
        # If no config or config doesn't mention it, include the kernel
        # (sched_ext might be built-in without a config entry).
        local config="/boot/config-$ver"
        if [[ -f "$config" ]]; then
            if grep -q "CONFIG_SCHED_CLASS_EXT=n" "$config" 2>/dev/null; then
                continue
            fi
        fi
        kernels+=("$k")
    done
    printf '%s\n' "${kernels[@]}"
}

# ── Discover schedulers ──────────────────────────────────────────────
discover_schedulers() {
    local scheds=()
    local search_dirs=(
        "$ROOT_DIR/scx/scheds/rust_only/scx_simple/target/release"
        "$ROOT_DIR/scx/scheds/rust_only/scx_cosmos/target/release"
        "$ROOT_DIR/scx/scheds/rust_only/scx_mitosis/target/release"
    )
    local names=("scx_simple" "scx_cosmos_rs" "scx_mitosis_rs")

    for i in "${!search_dirs[@]}"; do
        local dir="${search_dirs[$i]}"
        local name="${names[$i]}"
        local bin="$dir/$name"
        [[ -x "$bin" ]] || continue

        # Apply filter
        if [[ -n "$FILTER_SCHEDULERS" ]]; then
            local match=false
            IFS=',' read -ra filters <<< "$FILTER_SCHEDULERS"
            for f in "${filters[@]}"; do
                if [[ "$name" == *"$f"* ]]; then
                    match=true
                    break
                fi
            done
            $match || continue
        fi
        # Output: name|path
        echo "$name|$bin"
    done
}

# ── Run single test ──────────────────────────────────────────────────
# Returns: "PASS", "FAIL", or "SKIP"
run_test() {
    local kernel="$1" sched_bin="$2" cpus="$3" timeout="$4" retries="$5"

    [[ -x "$RUN_IN_VM" ]] || { echo "SKIP"; return; }
    [[ -f "$kernel" ]] || { echo "SKIP"; return; }
    [[ -x "$sched_bin" ]] || { echo "SKIP"; return; }

    local attempt
    for attempt in $(seq 1 "$retries"); do
        local output
        output=$(VNG_KERNEL="$kernel" VNG_SMP="$cpus" VNG_MEM=2G VNG_NUMA=0 \
            "$RUN_IN_VM" "$sched_bin" "$timeout" 2>&1) || true

        if echo "$output" | grep -q "=== PASS"; then
            echo "PASS"
            return
        fi
        # On last attempt, report failure
        if [[ $attempt -eq $retries ]]; then
            echo "FAIL"
            return
        fi
        sleep 1
    done
    echo "FAIL"
}

# ── Main ─────────────────────────────────────────────────────────────

# Discover
mapfile -t KERNELS < <(discover_kernels)
mapfile -t SCHEDS < <(discover_schedulers)
IFS=',' read -ra TOPO_LIST <<< "$TOPOLOGIES"

if [[ ${#KERNELS[@]} -eq 0 ]]; then
    echo "${RED}No sched_ext kernels found in /boot/${RESET}" >&2
    exit 1
fi
if [[ ${#SCHEDS[@]} -eq 0 ]]; then
    echo "${RED}No scheduler binaries found. Build first.${RESET}" >&2
    exit 1
fi

# Print header
if ! $JSON; then
    echo "${BOLD}══════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}  Scheduler Test Matrix${RESET}"
    echo "${BOLD}══════════════════════════════════════════════════════════${RESET}"
    echo "  Kernels:     ${#KERNELS[@]}"
    echo "  Schedulers:  ${#SCHEDS[@]}"
    echo "  Topologies:  ${TOPO_LIST[*]}"
    echo "  Timeout:     ${TIMEOUT}s"
    echo "  Retries:     ${RETRIES}"
    echo "  Stress:      $STRESS"
    echo ""
fi

# Run matrix
declare -A RESULTS
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

JSON_ENTRIES=""

for kernel in "${KERNELS[@]}"; do
    kver="${kernel#/boot/vmlinuz-}"
    # Shorten for display: keep major.minor.patch
    kshort=$(echo "$kver" | grep -oP '^\d+\.\d+(\.\d+)?' || echo "$kver" | cut -d- -f1)

    for sched_entry in "${SCHEDS[@]}"; do
        IFS='|' read -r sname spath <<< "$sched_entry"

        for cpus in "${TOPO_LIST[@]}"; do
            TOTAL=$((TOTAL + 1))
            label="$kshort × $sname × ${cpus}cpu"

            if ! $JSON; then
                printf "  %-50s " "$label"
            fi

            result=$(run_test "$kernel" "$spath" "$cpus" "$TIMEOUT" "$RETRIES")
            RESULTS["$label"]="$result"

            case "$result" in
                PASS)
                    PASSED=$((PASSED + 1))
                    $JSON || printf "${GREEN}PASS${RESET}\n"
                    ;;
                FAIL)
                    FAILED=$((FAILED + 1))
                    $JSON || printf "${RED}FAIL${RESET}\n"
                    ;;
                SKIP)
                    SKIPPED=$((SKIPPED + 1))
                    $JSON || printf "${YELLOW}SKIP${RESET}\n"
                    ;;
            esac

            # JSON accumulation
            if $JSON; then
                [[ -n "$JSON_ENTRIES" ]] && JSON_ENTRIES="$JSON_ENTRIES,"
                JSON_ENTRIES="$JSON_ENTRIES{\"kernel\":\"$kshort\",\"scheduler\":\"$sname\",\"cpus\":$cpus,\"result\":\"$result\"}"
            fi
        done
    done
done

# Stress tests
if $STRESS && [[ -x "$STRESS_COMBO" ]]; then
    for kernel in "${KERNELS[@]}"; do
        kver="${kernel#/boot/vmlinuz-}"
        kshort=$(echo "$kver" | sed 's/-0_fbk.*//;s/-0_.*$//')

        TOTAL=$((TOTAL + 1))
        label="$kshort × mitosis-stress-combo"

        if ! $JSON; then
            printf "  %-50s " "$label"
        fi

        result=$(run_test "$kernel" "$STRESS_COMBO" "8" "60" "$RETRIES")
        RESULTS["$label"]="$result"

        case "$result" in
            PASS) PASSED=$((PASSED + 1)); $JSON || printf "${GREEN}PASS${RESET}\n" ;;
            FAIL) FAILED=$((FAILED + 1)); $JSON || printf "${RED}FAIL${RESET}\n" ;;
            SKIP) SKIPPED=$((SKIPPED + 1)); $JSON || printf "${YELLOW}SKIP${RESET}\n" ;;
        esac

        if $JSON; then
            [[ -n "$JSON_ENTRIES" ]] && JSON_ENTRIES="$JSON_ENTRIES,"
            JSON_ENTRIES="$JSON_ENTRIES{\"kernel\":\"$kshort\",\"scheduler\":\"mitosis-stress-combo\",\"cpus\":8,\"result\":\"$result\"}"
        fi
    done
fi

# ── Output ───────────────────────────────────────────────────────────
if $JSON; then
    cat <<ENDJSON
{
  "total": $TOTAL,
  "passed": $PASSED,
  "failed": $FAILED,
  "skipped": $SKIPPED,
  "results": [$JSON_ENTRIES]
}
ENDJSON
else
    echo ""
    echo "${BOLD}──────────────────────────────────────────────────────────${RESET}"
    printf "  Total: %d  ${GREEN}Pass: %d${RESET}  ${RED}Fail: %d${RESET}  ${YELLOW}Skip: %d${RESET}\n" \
        "$TOTAL" "$PASSED" "$FAILED" "$SKIPPED"
    echo "${BOLD}──────────────────────────────────────────────────────────${RESET}"
fi

# Exit code
if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
