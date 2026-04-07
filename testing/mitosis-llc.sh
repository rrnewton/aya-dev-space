#!/bin/bash
# mitosis-llc.sh — wrapper to run scx_mitosis_rs with LLC awareness
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/../scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs" --enable-llc-awareness "$@"
