#!/bin/bash
# mitosis-llc-steal.sh — wrapper to run scx_mitosis_rs with LLC awareness + work stealing
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/../scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs" --enable-llc-awareness --enable-work-stealing "$@"
