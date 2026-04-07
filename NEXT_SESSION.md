# Next Session Planning — aya-rs.dev

**Last updated**: 2026-04-07
**Status**: scx_mitosis runs on 6.13, 5 PORT_TODOs remain, kptr fixup landed

## Current State

| Metric | Value |
|--------|-------|
| PORT_TODOs remaining | **5** (was 77 at project start) |
| Total commits (session) | **85** (41 parent + 22 scx + 22 aya) |
| Unit tests | 307 pass, 0 fail (aya:107, arena:65, postprocessor:32, aya-obj:103) |
| VM tests | 33+ pass on kernel 6.13 (3 schedulers × topologies + stress) |
| Kernel support | 6.13 ✅, 6.16 scx_simple ✅ (struct_ops fix), 6.16 mitosis ❌ (verifier) |
| Schedulers verified | scx_simple ✅, scx_cosmos ✅, scx_mitosis ✅ (all on 6.13) |
| scx_mitosis BPF LOC | 2,124 |
| scx_mitosis total LOC | 3,639 (BPF + userspace + stats + topology) |
| scx_mitosis callbacks | 15 struct_ops + 3 aux programs (100% of C original) |
| Topologies tested | 1, 2, 3, 4, 8, 16, 32 CPUs; NUMA/flat; SMT/no-SMT |

### 5 Remaining PORT_TODOs

| Line | Issue | Blocker |
|------|-------|---------|
| 264 | TaskCtx cpumask: `u64` placeholder, not `Kptr<bpf_cpumask>` | aya-55: kptr in task storage |
| 762 | `update_task_cpumask()` not implemented | Depends on TaskCtx kptr |
| 1002 | `get_cgroup_cpumask()` cpuset introspection stubbed | aya-33: CO-RE `bpf_core_type_matches` |
| 1015 | (same as above — the implementation line) | aya-33 |
| 1036 | `bpf_for_each(css, ...)` cgroup iterator stubbed | No Rust equivalent for open-coded iterators |

### Open Beads Issues

| Issue | Title | Priority |
|-------|-------|----------|
| aya-33 | eBPF-side struct_ops hackiness (compiler limitations) | P3 |
| aya-35 | Eliminate inline asm kfunc wrappers | P3 |
| aya-41 | Investigate LLVM BPFAbstractMemberAccess in rustc | P3 |
| aya-56 | Cosmos/mitosis fail on 6.16+: verifier + CO-RE issues | P2 |

---

## Priority 1: Immediate (Next Session, ~4-6 hours)

### 1A. Fix TaskCtx cpumask kptr (PORT_TODO line 264) — 2 hours

The map-value kptr BTF fixup just landed (`3eb9ed89`). Now implement the
consumer code:

1. **Change `TaskCtx.cpumask_placeholder: u64` → `cpumask: Kptr<bpf_cpumask>`**
   - Update `TaskCtx::ZERO` to use `Kptr::zeroed()`
   - Fix any size/offset assumptions

2. **Create per-task cpumask in `init_task`**:
   ```rust
   let mask = cpumask::create();
   if mask.is_null() { return -12; }
   let old = unsafe { kptr_xchg(&raw mut tctx.cpumask, mask) };
   if !old.is_null() { cpumask::release(old); }
   ```

3. **Implement `update_task_cpumask(p, tctx)`** (~60 lines):
   - `rcu_read_lock()`
   - Read cell cpumask via `lookup_cell_cpumask(tctx.cell)` (already exists)
   - Read task cpumask via `Kptr::get(&raw const tctx.cpumask)`
   - Intersect: `cpumask::and(task_mask, cell_mask, p->cpus_ptr)`
   - Check `cpumask::subset()` for `all_cell_cpus_allowed`
   - Route to per-CPU DSQ or cell+LLC DSQ
   - `rcu_read_unlock()`

4. **Wire `update_task_cpumask` into callers**:
   - `update_task_cell()` (line 804)
   - `set_cpumask()` callback (line 1611)
   - `maybe_retag_stolen_task()` (line 1278)

5. **Implement `pick_idle_cpu()` using task cpumask** (~50 lines):
   - Use `kfuncs::get_idle_smtmask()`, `kfuncs::pick_idle_cpu()`
   - Replace `select_cpu_dfl` fallback in `mitosis_select_cpu`

6. **Initialize `ALL_CPUMASK` global** in `mitosis_init()`:
   - `cpumask::create()` + `cpumask::set_cpu()` loop + `kptr_xchg`

**Verification**: Build, load on 6.13 VM, verify kptr operations pass verifier.

### 1B. Remove stale PORT_TODO comments — 15 min

Several PORT_TODOs describe infrastructure that already exists. Clean them up:
- Line 413: `cell_cpumask_wrapper` (exists at line 444)
- Line 433: `cell_cpumasks` map (exists at line 449)
- Line 489: `ALL_CPUMASK` (already declared)
- Line 721: `lookup_cell_cpumask` (exists at line 735)
- Line 1647: cell cpumask init (exists at lines 1717-1759)

### 1C. Kernel 6.16+ support (aya-56) — 2-3 hours

Two blockers remain for 6.16+ kernels:

**Blocker 1: Verifier complexity** — `enqueue` exceeds 1M instructions because
`pick_idle_cpu_preferred` is inlined. Fix: make it `#[inline(never)]` (BPF
subprogram). Needs testing — the verifier's subprogram support for struct_ops
can be finicky.

**Blocker 2: CO-RE type mismatch** — The postprocessor uses `__u64` placeholder
types for all CO-RE fields, but `task_struct.scx.flags` is `u32`. Fix: use
actual vmlinux field types from BTF instead of placeholders. This requires
changes to `aya-core-postprocessor/src/btf_parser.rs`.

Both are documented in `aya-56`. The `core_write!` → kfunc migration is already
done (cosmos uses `task_set_dsq_vtime` / `task_set_slice` behind `kernel_6_16`
feature flag).

---

## Priority 2: Short-term (1-2 Sessions)

### 2A. Cgroup hierarchy iteration (PORT_TODO line 1036) — 3-4 hours

The timer callback (`update_timer_cb`) needs to walk the cgroup tree using
`bpf_for_each(css, pos, root_css, BPF_CGROUP_ITER_DESCENDANTS_PRE)`. This
is an open-coded BPF iterator with no Rust equivalent.

**Options (pick one):**
1. **C shim**: Write a small C BPF helper that calls the iterator and invokes
   a Rust callback via function pointer. Link into the same ELF.
2. **Userspace-driven**: Have userspace periodically enumerate cgroups via
   `/sys/fs/cgroup` and push cell assignments via a BPF map.
3. **Bounded loop**: Use `bpf_cgroup_from_id()` in a bounded loop with known
   cgroup IDs from a userspace-maintained list.

Option 2 is simplest and most portable. Option 1 is most faithful to the C
version. Research needed to determine which approach works with the verifier.

### 2B. Cpuset introspection (PORT_TODO lines 1002/1015) — 2-3 hours

`get_cgroup_cpumask()` needs to read `cpuset->cpus_allowed` from a cgroup's
cpuset controller. The C version uses `bpf_core_type_matches()` to handle
two possible kernel layouts (pointer vs in-situ array).

**Options:**
1. **vmlinux bindgen**: Add `cpuset` struct to `scx_vmlinux::generate()` with
   the `cpus_allowed` field. Use `core_read!` with the generated type.
2. **Fixed layout**: Use `core_read!` with a specific kernel version's layout.
   Less portable but simpler.
3. **C shim**: A 10-line C function that reads cpuset cpumask using
   `bpf_core_type_matches` and returns it via a shared buffer.

Option 3 is most robust. Option 1 requires vmlinux changes.

### 2C. Performance benchmarking on bare metal — 2 hours

All testing so far has been in VMs. Bare-metal testing on a 6.13+ host would
validate real-world performance:

```bash
# Quick comparison (already scripted)
cd testing && bash quick-bench.sh

# Full comparison (CPU, pipe, fork workloads)
cd testing && bash benchmark-compare.sh
```

Key metrics to collect:
- Scheduling latency (P50/P99/P999)
- CPU throughput (matrixprod bogo-ops/s)
- Context switch overhead
- CFS vs scx_mitosis comparison

### 2D. GitHub Actions CI — 2-3 hours

Set up CI to catch regressions:
1. `cargo build --release` for all three schedulers
2. `cargo test -p aya-obj` (102 unit tests)
3. `cargo clippy` on both aya and scx workspaces
4. Optionally: VM-based integration test on a self-hosted runner

---

## Priority 3: Medium-term (Future Sessions)

### 3A. Full 6.16+ / 6.18+ kernel support

- Resolve CO-RE type mismatch (use vmlinux field types, not `__u64` placeholders)
- Resolve verifier complexity (subprograms for large functions)
- Test on 6.18-rc kernels where `task_set_dsq_vtime` / `task_set_slice` are available
- struct_ops layout changes between kernel versions

### 3B. Arena library integration into aya upstream

The arena data structures (`aya-arena-common`) have 65 passing tests but are
not yet integrated into the aya crate proper:
- HashMap, B-tree, linked list, slab allocator
- Shared-memory BPF arena (`BPF_MAP_TYPE_ARENA`)
- Needs API review and documentation

### 3C. Upstream aya contributions

Key fixes that should go upstream:
- CO-RE postprocessor stale relocation fix (`4c86ba5a`)
- `fixup_kptr_types` struct member support (`3eb9ed89`)
- `BPF_MAP_TYPE_CGRP_STORAGE` support
- `BPF_MAP_TYPE_ARENA` support

### 3D. Multi-scheduler testing framework

A framework for running all three schedulers under various workloads and
comparing results:
- Workloads: CPU-bound, I/O-bound, mixed, cgroup-isolated
- Metrics: latency, throughput, fairness, power
- Automated comparison reports

### 3E. aya-ebpf compiler improvements (aya-33, aya-35, aya-41)

Long-term compiler work:
- Eliminate inline asm kfunc wrappers (needs rustc BPF backend changes)
- Enable LLVM `BPFAbstractMemberAccess` pass for native CO-RE
- `#[struct_ops]` proc macro for type-safe callback registration

---

## Reference Documents

| Document | Contents |
|----------|----------|
| `KPTR_ROADMAP.md` | Kptr infrastructure gap analysis, 21 PORT_TODOs, implementation plan |
| `PERFORMANCE_REPORT.md` | Scheduler comparison, benchmark methodology, kernel compatibility |
| `MITOSIS_E2E_REPORT.md` | End-to-end testing results, 14 callbacks verified |
| `SESSION_REPORT.md` | Previous session achievements, commit log |
| `ARCHITECTURE.md` | Project layout, build system, submodule structure |
| `docs/cosmos-port-mapping.md` | C→Rust function mapping for cosmos |
| `.beads/` | Issue tracker (minibeads), `mb list` for status |

## Quick Reference: Key Commits

| Hash | Description |
|------|-------------|
| `4c86ba5a` | CO-RE postprocessor: fix stale BTF.ext relocation corruption |
| `3eb9ed89` | fixup_kptr_types: extend to rewrite STRUCT members (this session) |
| `b3421a81` | CO-RE postprocessor: regression tests (32 tests) |
| `61ba567f` | scx_mitosis: PORT_TODO reduction 49→24 |
| `34a5acde` | scx_mitosis: BPF timer for cell reconfiguration |
| `84615fab` | scx_mitosis: spin locks, cpumask kptrs, CO-RE reads |
