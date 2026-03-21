#!/bin/bash
#
# compare-results.sh — Compare two benchmark result sets.
#
# Usage:
#   ./testing/compare-results.sh <results-dir-A> <results-dir-B>
#
# Example:
#   ./testing/compare-results.sh results/standard-cosmos results/purerust-cosmos
#
# Reads summary.json from each directory and produces a side-by-side
# comparison with percentage differences.

set -euo pipefail

DIR_A="${1:-}"
DIR_B="${2:-}"

if [[ -z "$DIR_A" || -z "$DIR_B" ]]; then
    echo "Usage: $0 <results-dir-A> <results-dir-B>" >&2
    exit 1
fi

FILE_A="$DIR_A/summary.json"
FILE_B="$DIR_B/summary.json"

for f in "$FILE_A" "$FILE_B"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: $f does not exist" >&2
        exit 1
    fi
done

# Extract scheduler names from the JSON files.
sched_a=$(grep '"scheduler"' "$FILE_A" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
sched_b=$(grep '"scheduler"' "$FILE_B" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')

# If both are the same name, use directory basenames to differentiate.
if [[ "$sched_a" == "$sched_b" ]]; then
    label_a="$(basename "$DIR_A")"
    label_b="$(basename "$DIR_B")"
else
    label_a="$sched_a"
    label_b="$sched_b"
fi

echo "================================================================"
echo " Benchmark Comparison"
echo " A: $label_a ($DIR_A)"
echo " B: $label_b ($DIR_B)"
echo "================================================================"
echo ""

# Extract all metric keys from both files.
# This is a simple grep-based approach that doesn't require jq.
extract_metrics() {
    local file="$1"
    # Find lines in the metrics block that look like "key": value
    sed -n '/"metrics"/,/^  }/p' "$file" | \
        grep -E '^\s+"[a-z_]' | \
        sed 's/.*"\([^"]*\)": *\(.*\)/\1 \2/' | \
        sed 's/,$//' | sed 's/"//g'
}

declare -A METRICS_A METRICS_B

while IFS=' ' read -r key value; do
    METRICS_A["$key"]="$value"
done < <(extract_metrics "$FILE_A")

while IFS=' ' read -r key value; do
    METRICS_B["$key"]="$value"
done < <(extract_metrics "$FILE_B")

# Merge all keys.
ALL_KEYS=$(echo "${!METRICS_A[@]} ${!METRICS_B[@]}" | tr ' ' '\n' | sort -u)

# Determine which metrics are "lower is better" vs "higher is better".
# By convention:
#   - *_time_*, *_us, *_max_* → lower is better
#   - *_ops_*, *_per_sec      → higher is better
lower_is_better() {
    local key="$1"
    case "$key" in
        *time*|*_us|*_max_*|*latency*) return 0 ;;
        *) return 1 ;;
    esac
}

# Print header.
printf "%-40s  %15s  %15s  %10s  %s\n" "Metric" "$label_a" "$label_b" "Delta" "Verdict"
printf "%-40s  %15s  %15s  %10s  %s\n" \
    "$(printf '%0.s-' {1..40})" \
    "$(printf '%0.s-' {1..15})" \
    "$(printf '%0.s-' {1..15})" \
    "$(printf '%0.s-' {1..10})" \
    "$(printf '%0.s-' {1..10})"

for key in $ALL_KEYS; do
    val_a="${METRICS_A[$key]:-N/A}"
    val_b="${METRICS_B[$key]:-N/A}"

    delta=""
    verdict=""

    # Compute percentage difference if both values are numeric.
    if [[ "$val_a" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$val_b" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        if [[ "$val_a" != "0" ]]; then
            # delta = ((B - A) / A) * 100
            delta=$(awk "BEGIN { printf \"%.1f%%\", (($val_b - $val_a) / $val_a) * 100 }")

            # Determine verdict.
            local pct
            pct=$(awk "BEGIN { printf \"%.1f\", (($val_b - $val_a) / $val_a) * 100 }")

            if lower_is_better "$key"; then
                if awk "BEGIN { exit ($pct < -2) ? 0 : 1 }"; then
                    verdict="B wins"
                elif awk "BEGIN { exit ($pct > 2) ? 0 : 1 }"; then
                    verdict="A wins"
                else
                    verdict="~same"
                fi
            else
                if awk "BEGIN { exit ($pct > 2) ? 0 : 1 }"; then
                    verdict="B wins"
                elif awk "BEGIN { exit ($pct < -2) ? 0 : 1 }"; then
                    verdict="A wins"
                else
                    verdict="~same"
                fi
            fi
        fi
    fi

    printf "%-40s  %15s  %15s  %10s  %s\n" "$key" "$val_a" "$val_b" "$delta" "$verdict"
done

echo ""
echo "Delta = ((B - A) / A) * 100"
echo "Verdict threshold: >2% difference = winner, <=2% = ~same"
echo ""
echo "Lower is better: *_time_*, *_us, *_max_*"
echo "Higher is better: *_ops_*, *_per_sec"
