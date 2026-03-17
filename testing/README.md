# VM-based Scheduler Testing

Test BPF schedulers safely inside a lightweight VM using
[virtme-ng](https://github.com/arighi/virtme-ng).

The VM boots the host kernel in a QEMU VM that shares the host filesystem,
so scheduler binaries are accessible without copying.  The VM runs as
root, which is required for attaching sched-ext schedulers.

## Prerequisites

- `virtme-run` (from virtme-ng) installed and on `$PATH`
- A built kernel with sched-ext support (the host kernel is used)
- `script` (from util-linux, usually pre-installed)

## VM Topology

By default the VM runs with a realistic multi-domain topology:

| Feature | Default | Environment Variable |
|---------|---------|---------------------|
| vCPUs | 16 (2 sockets x 4 cores x 2 threads) | `VNG_SMP` |
| Memory | 2G | `VNG_MEM` |
| NUMA | 2 nodes (8 CPUs each) | `VNG_NUMA` (set "0" to disable) |
| AMD topoext | enabled (exposes SMT to guest) | `VNG_TOPOEXT` (set "0" to disable) |

This exercises:
- **NUMA awareness** — scheduler sees 2 NUMA nodes with different memory latencies
- **SMT handling** — scheduler sees 2 threads per core (via AMD topoext)
- **Multi-socket** — scheduler sees 2 sockets

**Note:** QEMU does not simulate L3 cache / CCX subdivision within a NUMA
node.  All cores in a node share one L3 cache.  LLC-aware scheduling
features won't see multiple cache groups per NUMA node.

### Custom topology examples

```bash
# Simple 4-CPU VM, no NUMA, no topology
VNG_SMP=4 VNG_NUMA=0 ./testing/run-in-vm.sh <binary>

# 32 CPUs across 4 NUMA nodes (requires matching VNG_MEM)
VNG_SMP="32,sockets=4,cores=4,threads=2" VNG_MEM=4G ./testing/run-in-vm.sh <binary>
```

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

# Run scx_cosmos for 30 seconds with verbose output
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

1. A thin QEMU wrapper is created to add `topoext=on` to `-cpu host`
   (needed on AMD hosts for SMT topology exposure)
2. `virtme-run` boots the host kernel in a QEMU VM with the configured
   topology (SMP, NUMA, memory)
3. The host filesystem is shared via 9p/virtiofs (read-only by default)
4. The scheduler binary runs as root under `timeout(1)`
5. After the duration elapses, `timeout` sends SIGTERM for clean detach
6. The VM shuts down and the script reports pass/fail

## Troubleshooting

**"not a valid pts"** — virtme-run requires a PTY. The scripts handle this
automatically with `script(1)`, but if you see this error when running
virtme-run directly, use `tmux`, `screen`, or wrap with `script -qc '...' /dev/null`.

**Scheduler fails to attach** — The host kernel must have sched-ext
support compiled in (`CONFIG_SCHED_CLASS_EXT=y`). Check with:
```bash
zcat /proc/config.gz | grep SCHED_CLASS_EXT
```

**SMT not detected in VM** — If `lscpu` inside the VM shows
"Thread(s) per core: 1", the topoext workaround may not be working.
Ensure `VNG_TOPOEXT=1` (default) and that the host CPU is AMD.
Intel hosts should expose SMT automatically without the workaround.
