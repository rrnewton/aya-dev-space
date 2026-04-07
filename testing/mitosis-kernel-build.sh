#!/bin/bash
# mitosis-kernel-build.sh — Start mitosis scheduler + run kernel compile workload
# This tests the scheduler with a real compilation workload (many short-lived
# processes, heavy I/O, parallel make).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER_BIN="$SCRIPT_DIR/../scx/scheds/rust_only/scx_mitosis/target/release/scx_mitosis_rs"

echo "═══ MITOSIS KERNEL BUILD TEST ═══"
echo "Kernel: $(uname -r)"
echo "CPUs: $(nproc)"

# Start scheduler
"$SCHEDULER_BIN" &
SCHED_PID=$!
sleep 3

if [ -f /sys/kernel/sched_ext/root/ops ]; then
    echo "Scheduler attached: $(cat /sys/kernel/sched_ext/root/ops)"
fi

START=$(date +%s)

# Try kernel build if source available
if [ -d /usr/src/linux ] && command -v make &>/dev/null; then
    echo "Running: make -C /usr/src/linux defconfig && make -j$(nproc)"
    make -C /usr/src/linux defconfig 2>&1 | tail -1
    timeout 300 make -C /usr/src/linux -j$(nproc) 2>&1 | tail -5
    echo "Kernel build phase complete"
elif command -v make &>/dev/null; then
    # No kernel source — simulate with a heavy make-like workload
    echo "No kernel source — running parallel compilation simulation"
    TMPDIR=$(mktemp -d)
    # Create 100 small C files to compile
    for i in $(seq 100); do
        cat > "$TMPDIR/file_$i.c" << 'CEOF'
#include <stdio.h>
int main() { int sum = 0; for (int i = 0; i < 1000000; i++) sum += i; return sum > 0 ? 0 : 1; }
CEOF
    done
    # Create Makefile
    cat > "$TMPDIR/Makefile" << 'MEOF'
CC = gcc
SRCS = $(wildcard *.c)
OBJS = $(SRCS:.c=.o)
all: $(OBJS)
%.o: %.c
	$(CC) -O2 -c $< -o $@
clean:
	rm -f *.o
MEOF
    echo "Compiling 100 files with make -j$(nproc)..."
    make -C "$TMPDIR" -j$(nproc) 2>&1 | tail -3
    echo "Compilation complete: $(ls "$TMPDIR"/*.o 2>/dev/null | wc -l) objects built"
    rm -rf "$TMPDIR"
else
    echo "No make available — running process creation stress instead"
    for round in $(seq 5); do
        for i in $(seq 50); do /bin/true & done
        wait
    done
    echo "Process creation stress complete"
fi

END=$(date +%s)
ELAPSED=$((END - START))

# Check scheduler survived
if kill -0 "$SCHED_PID" 2>/dev/null; then
    OPS=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo "unknown")
    echo ""
    echo "✅ Scheduler still running after ${ELAPSED}s (ops=$OPS)"
else
    echo ""
    echo "❌ Scheduler died during workload!"
    exit 1
fi

# Keep running until timeout kills us
echo "Waiting for timeout..."
wait "$SCHED_PID" 2>/dev/null || true
