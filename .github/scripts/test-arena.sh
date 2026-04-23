#!/bin/bash
set -euo pipefail
#
# test-arena.sh — Boot a kernel in virtme-ng and run arena integration tests.
#
# Usage:
#   ./test-arena.sh <kernel-bzImage> <test-binary>
#
# The test binary is built with AYA_BUILD_INTEGRATION_BPF=true and contains
# BPF programs that exercise arena data structures on real kernels.

KERNEL="${1:?Usage: $0 <bzImage> <test-binary>}"
TEST_BIN="${2:?Usage: $0 <bzImage> <test-binary>}"

GUEST_TIMEOUT=120

if [[ ! -f "$KERNEL" ]]; then
    echo "ERROR: kernel image not found: $KERNEL" >&2
    exit 1
fi
if [[ ! -f "$TEST_BIN" ]]; then
    echo "ERROR: test binary not found: $TEST_BIN" >&2
    exit 1
fi
if ! command -v vng &>/dev/null; then
    echo "ERROR: vng (virtme-ng) not found" >&2
    exit 1
fi

echo "=== test-arena: integration tests on $(basename "$KERNEL") ==="

rm -f /tmp/test-arena-output

VM_SCRIPT_FILE=$(mktemp /tmp/test-arena-XXXXXX.sh)
cat > "$VM_SCRIPT_FILE" <<INNEREOF
#!/bin/bash
set -e
echo ">>> Running arena integration tests ..."

# Run only arena tests (skip tests that need network namespaces etc.)
$TEST_BIN --test-threads=1 arena 2>&1 || {
    echo ">>> FAILED: arena integration tests"
    exit 1
}

echo ">>> Checking dmesg for errors ..."
dmesg > /tmp/dmesg.log
if grep -iE 'BUG:|WARNING:|Kernel panic|KASAN|UBSAN|general protection fault' /tmp/dmesg.log | \
   grep -v 'Speculative Return Stack Overflow' | \
   grep -v 'RETBleed:' | \
   grep -v 'Command line:' | \
   grep -v 'Kernel command line:' | \
   grep -qiE 'BUG:|WARNING:|Kernel panic|KASAN|UBSAN|general protection fault'; then
    echo ">>> KERNEL ERRORS DETECTED:"
    grep -iE 'BUG:|WARNING:|Kernel panic|KASAN|UBSAN|general protection fault' /tmp/dmesg.log | \
      grep -v 'Speculative Return Stack Overflow' | \
      grep -v 'RETBleed:' | \
      grep -v 'Command line:'
    echo ">>> FAILED: kernel errors found"
    exit 1
fi

echo ">>> PASSED: arena integration tests"
INNEREOF
chmod +x "$VM_SCRIPT_FILE"

timeout --preserve-status ${GUEST_TIMEOUT} \
    vng --user root -m 4G --cpus 4 --rw -v -r "$KERNEL" \
        --exec "bash $VM_SCRIPT_FILE" \
        2> >(tee /tmp/test-arena-output) </dev/null

if grep -q "FAILED" /tmp/test-arena-output 2>/dev/null; then
    echo "=== FAIL: arena integration tests ==="
    cp /tmp/test-arena-output test-arena.ci.log 2>/dev/null || true
    exit 1
fi

if grep -v \
    -e "Speculative Return Stack Overflow" \
    -e "RETBleed:" \
    /tmp/test-arena-output 2>/dev/null | \
    grep -qiE '\bBUG:\b|\bWARNING:\b|Kernel panic'; then
    echo "=== FAIL: arena integration tests (kernel errors) ==="
    cp /tmp/test-arena-output test-arena.ci.log 2>/dev/null || true
    exit 1
fi

cp /tmp/test-arena-output test-arena.ci.log 2>/dev/null || true
echo "=== PASS: arena integration tests ==="
exit 0
