# VM-based Scheduler Testing

Test BPF schedulers safely inside a lightweight VM using
[virtme-ng](https://github.com/arighi/virtme-ng) (VNG).

VNG boots the host kernel in a QEMU VM that shares the host filesystem,
so scheduler binaries are accessible without copying.  The VM runs as
root, which is required for attaching sched-ext schedulers.

## Prerequisites

- `vng` (virtme-ng) installed and on `$PATH`
- A built kernel with sched-ext support (the host kernel is used)
- `script` (from util-linux, usually pre-installed)

## Scripts

### run-in-vm.sh

Run a single scheduler binary in a VM for a given duration.

```bash
./testing/run-in-vm.sh <scheduler-binary> [duration-seconds]
```

Examples:

```bash
# Run scx_simple for 20 seconds (default)
./testing/run-in-vm.sh ./scx/scheds/rust_only/scx_simple/target/release/scx_simple

# Run scx_cosmos for 30 seconds with verbose VNG output
VERBOSE=1 ./testing/run-in-vm.sh ./scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos 30
```

Exit codes:
- `0` — scheduler ran successfully for the full duration (or exited cleanly)
- `1` — scheduler failed to attach or crashed

### test-all-schedulers.sh

Build and test all pure-Rust schedulers (scx_simple, scx_cosmos).

```bash
./testing/test-all-schedulers.sh [duration-seconds]
```

Options:
- `SKIP_BUILD=1` — skip the cargo build step, use existing binaries

```bash
# Full build + test, 10 seconds each
./testing/test-all-schedulers.sh 10

# Test only (binaries already built)
SKIP_BUILD=1 ./testing/test-all-schedulers.sh 15
```

## How it works

1. VNG boots the host kernel in a QEMU microVM
2. The host filesystem is shared via 9p/virtiofs (read-only by default)
3. The scheduler binary runs as root under `timeout(1)`
4. After the duration elapses, `timeout` sends SIGTERM for clean detach
5. The VM shuts down and the script reports pass/fail

## Troubleshooting

**"not a valid pts"** — VNG requires a PTY. The scripts handle this
automatically with `script(1)`, but if you see this error when running
VNG directly, use `tmux`, `screen`, or wrap with `script -qc '...' /dev/null`.

**Scheduler fails to attach** — The host kernel must have sched-ext
support compiled in (`CONFIG_SCHED_CLASS_EXT=y`). Check with:
```bash
zcat /proc/config.gz | grep SCHED_CLASS_EXT
```
