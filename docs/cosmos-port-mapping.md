# C cosmos to Rust cosmos BPF Scheduler Port Mapping

Detailed mapping between the C and pure-Rust implementations of the scx_cosmos BPF scheduler.

**C source**: `scx/scheds/rust/scx_cosmos/src/bpf/main.bpf.c` (1292 lines)
**Rust source**: `scx/scheds/rust_only/scx_cosmos/scx_cosmos-ebpf/src/main.rs` (2098 lines)

---

## 1. File Structure Mapping

### C file section order

| # | Section | C Lines | Rust Equivalent | Rust Lines |
|---|---------|---------|-----------------|------------|
| 1 | License + includes (`scx/common.bpf.h`, `scx/percpu.bpf.h`, `lib/pmu.h`, `intf.h`) | 1-10 | `#![no_std]`, `use scx_ebpf::*`, `mod vmlinux` | 50-72 |
| 2 | Constants/defines (`MAX_CPUS`, `MAX_NODES`, `SHARED_DSQ`, `CPUFREQ_*`) | 16-45 | `const` declarations | 169-222 |
| 3 | Global variables (`const volatile`, `volatile`, `static`) | 50-174 | `static mut` globals with `#[unsafe(no_mangle)]` | 232-414 |
| 4 | `struct task_ctx` + task_ctx_stor map | 178-192 | `struct TaskCtx` + `TASK_CTX: TaskStorage` | 93-122 |
| 5 | `cpu_node_map` (hash map) | 197-216 | `CPU_TO_NODE: [u32; MAX_CPUS]` flat array | 284-285 |
| 6 | `try_lookup_task_ctx()` | 221-225 | Inline `TASK_CTX.get(p)` calls | (inlined) |
| 7 | `struct cpu_ctx` + cpu_ctx_stor map | 230-251 | `struct CpuCtx` + `CPU_CTX: PerCpuArray` | 103-127 |
| 8 | `update_counters()` | 253-265 | `update_perf_counters()` | 1168-1179 |
| 9 | `is_event_heavy()` | 270-273 | `is_event_heavy()` | 1061-1064 |
| 10 | `calc_avg()` | 282-285 | `calc_avg()` | 701-703 |
| 11 | `update_freq()` | 294-300 | `update_freq()` | 711-719 |
| 12 | `update_cpu_load()` | 305-333 | `update_cpu_load()` | 730-755 |
| 13 | `update_cpufreq()` | 338-361 | `update_cpufreq()` | 764-785 |
| 14 | `struct wakeup_timer` + timer map | 369-378 | `struct WakeupTimer` + `WAKEUP_TIMER: BpfArray` | 159-167 |
| 15 | `shared_dsq()` | 383-386 | `shared_dsq()` | 635-647 |
| 16 | `is_pcpu_task()` | 392-394 | `is_pcpu_task()` | 610-617 |
| 17 | `is_system_busy()` | 403-406 | `is_system_busy()` | 623-625 |
| 18 | `is_cpu_idle()` | 411-427 | `is_cpu_idle()` | 812-862 |
| 19 | `smt_sibling()` | 432-446 | **NOT PORTED** | -- |
| 20 | `is_smt_contended()` | 455-473 | **NOT PORTED** | -- |
| 21 | `is_cpu_valid()` | 479-488 | Inline bounds checks | (inlined) |
| 22 | `cpus_share_cache()` | 494-503 | **NOT PORTED** | -- |
| 23 | `is_cpu_faster()` | 507-516 | `is_cpu_faster()` | 486-490 |
| 24 | `pick_idle_cpu_pref_smt()` | 523-559 | `pick_idle_cpu_preferred()` | 888-930 |
| 25 | `pick_idle_cpu_flat()` | 565-623 | **Simplified** -- merged into `pick_idle_cpu_preferred()` | 888-930 |
| 26 | `is_wakeup()` | 628-631 | **Inlined** as `(wake_flags & SCX_WAKE_TTWU) != 0` | 1346 |
| 27 | `pick_idle_cpu()` | 639-713 | `pick_idle_cpu()` | 974-1052 |
| 28 | `task_slice()` | 718-721 | `task_slice()` | 553-556 |
| 29 | `task_dl()` | 750-760 | Inlined in `on_enqueue()` phase 4 | 1536-1582 |
| 30 | `init_cpumask()` | 766-783 | `init_primary_cpumask()` | 1844-1866 |
| 31 | `enable_sibling_cpu` (SEC("syscall")) | 785-808 | **NOT PORTED** | -- |
| 32 | `enable_primary_cpu` (SEC("syscall")) | 813-830 | Replaced by `PRIMARY_CPU_LIST[]` global array | 330-331, 1912-1925 |
| 33 | `wakeup_timerfn()` | 838-862 | `wakeup_timerfn()` | 1210-1229 |
| 34 | `task_should_migrate()` | 867-874 | Inlined in `on_enqueue()` | 1486 |
| 35 | `is_wake_affine()` | 880-885 | `is_wake_affine()` | 503-536 |
| 36 | `pick_least_busy_event_cpu()` | 892-918 | `pick_least_busy_event_cpu()` + `least_busy_callback()` | 1101-1157 |
| 37 | `cosmos_select_cpu()` | 920-981 | `on_select_cpu()` | 1270-1405 |
| 38 | `wakeup_cpu()` | 986-995 | `wakeup_cpu()` | 1247-1252 |
| 39 | `cosmos_enqueue()` | 997-1062 | `on_enqueue()` | 1443-1591 |
| 40 | `cosmos_dispatch()` | 1064-1080 | `on_dispatch()` | 1603-1633 |
| 41 | `cosmos_runnable()` | 1082-1106 | `on_runnable()` | 1645-1660 |
| 42 | `cosmos_running()` | 1108-1138 | `on_running()` | 1678-1704 |
| 43 | `cosmos_stopping()` | 1140-1175 | `on_stopping()` | 1725-1773 |
| 44 | `cosmos_enable()` | 1177-1180 | `on_enable()` | 1779-1785 |
| 45 | `cosmos_init_task()` | 1182-1197 | `on_init_task()` | 1792-1798 |
| 46 | `cosmos_exit_task()` | 1199-1203 | `on_exit_task()` | 1809-1812 |
| 47 | `cosmos_init()` | 1205-1268 | `on_init()` | 1869-1961 |
| 48 | `cosmos_exit()` | 1270-1276 | `on_exit()` | 1971 |
| 49 | `SCX_OPS_DEFINE` | 1278-1291 | `scx_ops_define!` | 2070-2097 |

### Sections present only in Rust

| Section | Rust Lines | Description |
|---------|------------|-------------|
| `mod vmlinux` (generated bindgen) | 70-72 | Replaces C `#include <vmlinux.h>` |
| BPF helper wrappers (`get_current_task_btf`, `get_smp_processor_id`) | 422-457 | Inline asm for BPF helpers not available via kfuncs |
| `read_weight()` | 559-566 | Explicit helper; C uses `p->scx.weight` directly |
| `is_migration_disabled()` | 584-597 | Explicit CO-RE reimplementation of C macro from `common.bpf.h` |
| `time_before()` | 692-694 | Wrapping timestamp comparison; C uses kernel macro |
| `cpu_node()` inline-asm bounds check | 659-685 | BPF verifier workaround for Rust codegen |
| `LeastBusyCtx` struct | 1094-1099 | Context for `bpf_loop` callback pattern |
| `SCX_PMU_MAP`, `PMU_BASELINE` maps | 135-150 | PMU infrastructure maps for tracing program |
| `PRIMARY_CPU_LIST` global | 330-331 | Replaces C `enable_primary_cpu` syscall program |
| `scx_pmu_sched_switch` (tp_btf program) | 2007-2066 | Separate tracing program for PMU reads |
| `scx_ops_define!` `flags: 54` | 2085 | OPS flags set in BPF binary (C sets them at runtime) |

### Sections present only in C

| Section | C Lines | Description |
|---------|---------|-------------|
| `intf.h` includes (`cpu_arg`, `domain_arg` structs) | 8 (+ intf.h) | Rust has no equivalent (syscall programs eliminated) |
| `UEI_DEFINE(uei)` | 159 | User Exit Info definition -- not ported |
| `enable_sibling_cpu` SEC("syscall") | 785-808 | Replaced by different approach (see section 4) |
| `enable_primary_cpu` SEC("syscall") | 813-830 | Replaced by `PRIMARY_CPU_LIST` global |
| `smt_sibling()` | 432-446 | Requires per-CPU kptr cpumask (see section 4) |
| `is_smt_contended()` | 455-473 | Requires `smt_sibling()` and `get_idle_cpumask()` |
| `cpus_share_cache()` | 494-503 | Requires `cpu_llc_id()` from `common.bpf.h` |

---

## 2. Function-by-Function Mapping

| # | C Function | C Line | Rust Function | Rust Line | Port Status |
|---|-----------|--------|---------------|-----------|-------------|
| 1 | `cpu_node()` | 204 | `cpu_node()` | 659 | Different: C uses hash map lookup; Rust uses flat array with inline-asm bounds check |
| 2 | `try_lookup_task_ctx()` | 221 | (inlined) | -- | Replaced by `TASK_CTX.get(p)` calls at each use site |
| 3 | `try_lookup_cpu_ctx()` | 247 | (inlined) | -- | Replaced by `CPU_CTX.get_ptr_mut(0)` or `CPU_CTX.get_percpu()` at each use site |
| 4 | `update_counters()` | 253 | `update_perf_counters()` | 1168 | Different: C calls `scx_pmu_read()`; Rust stores delta from tracing program |
| 5 | `is_event_heavy()` | 270 | `is_event_heavy()` | 1061 | 1:1 (also checks `threshold > 0`) |
| 6 | `calc_avg()` | 282 | `calc_avg()` | 701 | 1:1 |
| 7 | `update_freq()` | 294 | `update_freq()` | 711 | 1:1 (adds div-by-zero guard) |
| 8 | `update_cpu_load()` | 305 | `update_cpu_load()` | 730 | Different: C takes `task_struct*`; Rust takes `(slice, now)`. Same logic. Rust uses current-CPU `get_ptr_mut(0)` instead of `bpf_map_lookup_percpu_elem` for specific CPU. |
| 9 | `update_cpufreq()` | 338 | `update_cpufreq()` | 764 | 1:1 |
| 10 | `shared_dsq()` | 383 | `shared_dsq()` | 635 | Different: C calls `cpu_node()` which does hash map lookup; Rust indexes flat array |
| 11 | `is_pcpu_task()` | 392 | `is_pcpu_task()` | 610 | 1:1 |
| 12 | `is_system_busy()` | 403 | `is_system_busy()` | 623 | 1:1 |
| 13 | `is_cpu_idle()` | 411 | `is_cpu_idle()` | 812 | Different: C uses `__COMPAT_scx_bpf_cpu_curr(cpu)` + RCU; Rust uses `scx_bpf_cpu_rq(cpu)` + inline `bpf_probe_read_kernel` for `rq->curr` and `curr->flags` to avoid subprogram calls in loops |
| 14 | `smt_sibling()` | 432 | **NOT PORTED** | -- | Requires per-CPU `struct bpf_cpumask __kptr *smt` in `cpu_ctx`. See PORT_TODO #1 |
| 15 | `is_smt_contended()` | 455 | **NOT PORTED** | -- | Depends on `smt_sibling()`. See PORT_TODO #2 |
| 16 | `is_cpu_valid()` | 479 | (inlined) | -- | Replaced by inline bounds checks at each use site |
| 17 | `cpus_share_cache()` | 494 | **NOT PORTED** | -- | Requires `cpu_llc_id()` from `scx/percpu.bpf.h`. See PORT_TODO #3 |
| 18 | `is_cpu_faster()` | 507 | `is_cpu_faster()` | 486 | Simplified: C uses `is_cpu_valid()` guard; Rust uses bounds check returning 0 |
| 19 | `pick_idle_cpu_pref_smt()` | 523 | `pick_idle_cpu_preferred()` | 888 | Simplified: no primary/SMT cpumask filtering (no `primary`, `smt` params). No `p->cpus_ptr` check. |
| 20 | `pick_idle_cpu_flat()` | 565 | (merged into `pick_idle_cpu_preferred`) | 888 | Simplified: C has multi-tier scan (primary+SMT, primary only, SMT only, any); Rust only has flat scan. See PORT_TODO #4 |
| 21 | `is_wakeup()` | 628 | (inlined) | 1346 | Inlined as `(wake_flags & SCX_WAKE_TTWU) != 0` |
| 22 | `pick_idle_cpu()` | 639 | `pick_idle_cpu()` | 974 | Different: C calls `bpf_ksym_exists(scx_bpf_select_cpu_and)` for runtime feature detection; Rust uses `#[cfg(feature = "kernel_6_16")]` compile-time gate. C has hybrid wake-affine with `cpus_share_cache`/`is_smt_contended` guards; Rust skips those guards. |
| 23 | `task_slice()` | 718 | `task_slice()` | 553 | Different: C takes `task_struct*` and calls `scale_by_task_weight()`; Rust takes `weight: u64` and does `slice_ns * weight / 100` |
| 24 | `task_dl()` | 750 | (inlined in `on_enqueue`) | 1536-1582 | 1:1 logic, inlined into enqueue phase 4 |
| 25 | `init_cpumask()` | 766 | `init_primary_cpumask()` | 1844 | 1:1 pattern (create + kptr_xchg + release old); Rust adds verification readback |
| 26 | `enable_sibling_cpu()` | 785 | **NOT PORTED** | -- | See PORT_TODO #5 |
| 27 | `enable_primary_cpu()` | 813 | `PRIMARY_CPU_LIST` + loop in `on_init()` | 1912-1925 | Replaced: C uses `bpf_prog_test_run` syscall program; Rust uses a global array populated by userspace before load |
| 28 | `wakeup_timerfn()` | 838 | `wakeup_timerfn()` | 1210 | Different: C checks `is_cpu_idle(cpu)` before kicking; Rust skips the check (see PORT_TODO #6) |
| 29 | `task_should_migrate()` | 867 | (inlined in `on_enqueue`) | 1486 | Inlined as `!is_running && (enq_flags & SCX_ENQ_CPU_SELECTED) == 0`. C uses `__COMPAT_is_enq_cpu_selected()` compat wrapper |
| 30 | `is_wake_affine()` | 880 | `is_wake_affine()` | 503 | 1:1 (CO-RE reads via `core_read!` macro) |
| 31 | `pick_least_busy_event_cpu()` | 892 | `pick_least_busy_event_cpu()` | 1125 | Different: uses `bpf_loop` callback pattern instead of `bpf_for`; skips `is_cpu_idle()` and `p->cpus_ptr` checks. See PORT_TODO #7 |
| 32 | `cosmos_select_cpu()` | 920 | `on_select_cpu()` | 1270 | Different: C validates `prev_cpu` against `p->cpus_ptr`; Rust skips (no CO-RE for cpumask). C does hybrid wake-affine inside `pick_idle_cpu`; Rust does it in `on_select_cpu` before calling `pick_idle_cpu`. See PORT_TODO #8 |
| 33 | `wakeup_cpu()` | 986 | `wakeup_cpu()` | 1247 | 1:1 |
| 34 | `cosmos_enqueue()` | 997 | `on_enqueue()` | 1443 | 1:1 logic in 4 phases. Minor: Rust tries `test_and_clear_cpu_idle(prev_cpu)` before `pick_idle_cpu()` in non-pcpu path |
| 35 | `cosmos_dispatch()` | 1064 | `on_dispatch()` | 1603 | 1:1. Rust reads `scx.flags` and `scx.weight` together as u64 to work around LLVM BPF backend bug |
| 36 | `cosmos_runnable()` | 1082 | `on_runnable()` | 1645 | 1:1 |
| 37 | `cosmos_running()` | 1108 | `on_running()` | 1678 | Different: C calls `scx_pmu_event_start()` for PMU baseline; Rust omits (helper #55 unavailable in struct_ops). See PORT_TODO #9 |
| 38 | `cosmos_stopping()` | 1140 | `on_stopping()` | 1725 | Different: C calls `scx_pmu_event_stop()` + `update_counters()` for PMU; Rust omits from struct_ops (handled by tracing program). Otherwise 1:1. |
| 39 | `cosmos_enable()` | 1177 | `on_enable()` | 1779 | 1:1 |
| 40 | `cosmos_init_task()` | 1182 | `on_init_task()` | 1792 | Different: C calls `scx_pmu_task_init(p)`; Rust omits (PMU handled by tracing program). Otherwise 1:1. |
| 41 | `cosmos_exit_task()` | 1199 | `on_exit_task()` | 1809 | Different: C calls `scx_pmu_task_fini(p)`; Rust just deletes task storage. |
| 42 | `cosmos_init()` | 1205 | `on_init()` | 1869 | Different: C calls `scx_pmu_install()` and has explicit CPU loop zeroing `perf_events`; Rust relies on kernel zero-init. Rust adds `PRIMARY_CPU_LIST` population. Timer setup 1:1. |
| 43 | `cosmos_exit()` | 1270 | `on_exit()` | 1971 | Different: C calls `scx_pmu_uninstall()` + `UEI_RECORD()`. Rust is a no-op. See PORT_TODO #10, #11. |

---

## 3. PORT_TODOs

### PORT_TODO #1: `smt_sibling()` not ported

**Comment (Rust line 1341-1345)**:
```
// NOTE: We skip the cpus_share_cache and is_smt_contended checks since
// they require per-CPU LLC IDs and SMT sibling masks which we don't
// have in the pure-Rust BPF context. This means we may redirect the
// idle scan to a faster core even when prev_cpu is in the same LLC and
// fully idle -- a minor suboptimality that select_cpu_dfl handles well.
```

**C functionality**: `smt_sibling(cpu)` (line 432) returns the SMT sibling of a CPU by reading a per-CPU `bpf_cpumask __kptr *smt` field from `cpu_ctx`. This cpumask is populated by the `enable_sibling_cpu` syscall program, called from userspace for each CPU.

**Why not ported**: The per-CPU kptr cpumask in `cpu_ctx` requires `enable_sibling_cpu` (a syscall BPF program) for population. The Rust port eliminated syscall programs. Additionally, storing `bpf_cpumask __kptr` in a per-CPU array requires kptr support in per-CPU maps, which may have additional verifier constraints.

**Classification**: Incomplete port. Could be addressed by adding an SMT sibling flat array (like `CPU_TO_NODE`) populated by userspace.

### PORT_TODO #2: `is_smt_contended()` not ported

**C functionality**: `is_smt_contended(cpu)` (line 455) checks whether the SMT sibling of `cpu` is busy by testing it against the idle cpumask. Returns true when the sibling is not idle AND there are other fully-idle SMT cores available. Used in `pick_idle_cpu()` (line 674) to avoid migrating a wakee when `prev_cpu` has a fully-idle core.

**Why not ported**: Depends on `smt_sibling()` (PORT_TODO #1). Also uses `scx_bpf_get_idle_cpumask()` kfunc which requires proper kfunc resolution for the returned cpumask pointer.

**Classification**: Incomplete port. Functional impact: on SMT systems, the Rust port may unnecessarily migrate tasks away from `prev_cpu` even when the whole core is idle, increasing cache misses.

### PORT_TODO #3: `cpus_share_cache()` not ported

**C functionality**: `cpus_share_cache(this_cpu, that_cpu)` (line 494) returns true if two CPUs share the same LLC (last-level cache). Uses `cpu_llc_id()` from `scx/percpu.bpf.h`.

**Why not ported**: `cpu_llc_id()` is a per-CPU BPF helper from the scx library headers. The pure-Rust port does not have access to these helpers. Could be addressed with a `CPU_TO_LLC` flat array populated by userspace (similar to `CPU_TO_NODE`).

**Classification**: Incomplete port. Used in hybrid wake-affine path (line 673). The Rust port skips the LLC guard entirely, which means on hybrid systems with multiple LLCs, the wakee may be moved to a faster core in a different LLC unnecessarily.

### PORT_TODO #4: `pick_idle_cpu_flat()` multi-tier scan not ported

**Comment (Rust line 887)**:
```
/// C reference: `pick_idle_cpu_pref_smt(p, prev_cpu, is_prev_allowed,
///              primary=NULL, smt=NULL)` -- the final tier in
///              `pick_idle_cpu_flat()` which scans system-wide with no
///              primary or SMT filtering.
```

**C functionality**: `pick_idle_cpu_flat()` (line 565) calls `pick_idle_cpu_pref_smt()` in four tiers:
1. Full-idle core in primary domain (primary + SMT masks)
2. Any idle CPU in primary domain (primary mask only)
3. Any full-idle core system-wide (SMT mask only)
4. Any idle CPU system-wide (no masks)

The Rust `pick_idle_cpu_preferred()` only implements tier 4 (no primary or SMT filtering).

**Why not ported**: Tiers 1-3 require the per-CPU SMT cpumask (from `cpu_ctx->smt`, populated by `enable_sibling_cpu`) and the `scx_bpf_get_idle_smtmask()` kfunc. Both require infrastructure not yet available in the Rust port.

**Classification**: Incomplete port. On systems where `flat_idle_scan` or `preferred_idle_scan` is enabled AND primary cpumask or SMT avoidance is desired, the Rust port will not prefer primary CPUs or full-idle cores during flat scanning.

### PORT_TODO #5: `enable_sibling_cpu` syscall program not ported

**C functionality**: `enable_sibling_cpu()` (line 785) is a `SEC("syscall")` BPF program invoked from userspace via `bpf_prog_test_run`. It populates the per-CPU `cpu_ctx->smt` kptr cpumask with the SMT sibling CPU ID.

**What replaced it**: Nothing. The Rust port does not have the `smt` field in `CpuCtx` and does not populate SMT topology. This is the root cause of PORT_TODOs #1, #2, and #4.

**Classification**: Incomplete port. The replacement approach would be an `SMT_SIBLINGS: [i32; MAX_CPUS]` global array mapping each CPU to its SMT sibling, populated by userspace before load.

### PORT_TODO #6: `wakeup_timerfn` skips `is_cpu_idle()` check

**Comment (Rust line 1204-1208)**:
```
/// Note: The C version also checks `is_cpu_idle(cpu)` using
/// `__COMPAT_scx_bpf_cpu_curr()`. We skip that check because
/// `SCX_KICK_IDLE` already makes the kick a no-op for non-idle CPUs,
/// and `scx_bpf_cpu_curr` is not available on all kernels (requires
/// the compat fallback via `scx_bpf_cpu_rq`).
```

**C functionality**: `wakeup_timerfn()` (line 851) checks both `scx_bpf_dsq_nr_queued()` AND `is_cpu_idle(cpu)` before kicking. The Rust version only checks `dsq_nr_queued()`.

**Classification**: Deliberate simplification. `SCX_KICK_IDLE` already makes the kick a no-op for non-idle CPUs, so the `is_cpu_idle()` check is an optimization to avoid unnecessary kfunc calls, not a correctness issue.

### PORT_TODO #7: `pick_least_busy_event_cpu` missing checks

**Comment (Rust line 1087-1091)**:
```
/// Note: The `p->cpus_ptr` affinity check from the C version is skipped
/// because CO-RE field access for cpumasks is not yet available.
/// Note: The `is_cpu_idle(cpu)` check from the C version is skipped
/// because the extra `bpf_probe_read_kernel` calls in the loop body
/// add too many branches, and the verifier's jump complexity limit (8192)
/// is easily exceeded.
```

**C functionality**: `pick_least_busy_event_cpu()` (line 892) checks three conditions per CPU:
1. `cpu_node(cpu) != cpu_node(prev_cpu)` -- same NUMA node
2. `!is_cpu_idle(cpu)` -- CPU is idle (not busy)
3. `!bpf_cpumask_test_cpu(cpu, p->cpus_ptr)` -- task can run there

The Rust version only checks condition 1.

**Classification**: Incomplete port / toolchain limitation. Missing `cpus_ptr` is a CO-RE limitation. Missing `is_cpu_idle` is a verifier complexity limitation. Impact: may select a busy CPU or a CPU the task can't run on for event-heavy tasks.

### PORT_TODO #8: `select_cpu` missing prev_cpu validation

**Comment (Rust line 1271-1282)**:
```
// NOTE: prev_cpu validation.
//
// The C cosmos validates prev_cpu against p->cpus_ptr:
//   if (!bpf_cpumask_test_cpu(prev_cpu, p->cpus_ptr))
//       prev_cpu = is_this_cpu_allowed ? this_cpu : bpf_cpumask_first(p->cpus_ptr);
//
// This requires CO-RE field access to p->cpus_ptr which we cannot do
// from Rust without generated vmlinux bindings for that field.
```

**C functionality**: `cosmos_select_cpu()` (line 933-934) validates `prev_cpu` against the task's allowed CPU mask. If `prev_cpu` is not allowed (e.g., after a cpuset change), it falls back to `this_cpu` or the first allowed CPU.

**Classification**: Toolchain limitation. The BPF verifier requires `cpus_ptr` to be accessed through CO-RE, and the Rust toolchain does not yet support this. Impact: rare, only affects tasks during cpuset membership changes.

### PORT_TODO #9: PMU `scx_pmu_event_start` / `scx_pmu_event_stop` in struct_ops

**Comment (Rust line 1669-1673)**:
```
/// NOTE: The C cosmos also calls scx_pmu_event_start(p, false) here when
/// perf_config is set, which reads bpf_perf_event_read_value to capture a
/// baseline counter value. We cannot do this because helper #55 is not
/// available in struct_ops programs.
```

**C functionality**: In `cosmos_running()` (line 1136-1137), `scx_pmu_event_start()` captures the perf counter baseline. In `cosmos_stopping()` (line 1151-1153), `scx_pmu_event_stop()` + `update_counters()` computes the delta.

**What replaced it**: A separate `tp_btf/sched_switch` tracing program (`scx_pmu_sched_switch`, Rust line 2009) that runs on every context switch and uses `bpf_perf_event_read_value` (helper #55). This is actually the same architecture the C cosmos uses (`scx/lib/pmu.bpf.c`).

**Classification**: Different approach (not incomplete). The tracing program approach matches the C PMU library's intended architecture. Functional equivalence is achieved.

### PORT_TODO #10: `UEI_RECORD` not ported

**Comment (Rust line 1967-1969)**:
```
/// C reference: cosmos_exit() calls scx_pmu_uninstall() when perf_config
/// is set, and UEI_RECORD(uei, ei) to save exit info for userspace.
/// ... UEI_RECORD is not yet ported (requires the UEI mechanism).
```

**C functionality**: `cosmos_exit()` (line 1275) calls `UEI_RECORD(uei, ei)` which stores the scheduler exit information (exit kind, reason, message) in a global struct for userspace to read after the scheduler detaches.

**Why not ported**: The UEI mechanism uses BPF macros (`UEI_DEFINE`, `UEI_RECORD`) that expand to global variables and helper calls. The Rust port does not have an equivalent UEI implementation.

**Classification**: Incomplete port. Impact: userspace cannot read the scheduler's exit reason (why it detached). This affects debugging but not scheduling correctness.

### PORT_TODO #11: `scx_pmu_uninstall` in exit not ported

**C functionality**: `cosmos_exit()` (line 1272-1273) calls `scx_pmu_uninstall(perf_config)` to clean up per-CPU perf events.

**What replaced it**: The Rust port relies on automatic map cleanup when the BPF program detaches.

**Classification**: Deliberate omission. The kernel cleans up BPF maps on program detach, so explicit cleanup is unnecessary.

### PORT_TODO #12: `nr_event_dispatches` counter not ported

**C functionality**: `cosmos_select_cpu()` (line 960) and `cosmos_enqueue()` (line 1019) increment `nr_event_dispatches` atomically with `__sync_fetch_and_add`. This is a statistics counter readable by userspace.

**Why not ported**: The Rust port does not have an equivalent atomic counter. This is purely a diagnostics omission.

**Classification**: Incomplete port. Impact: userspace cannot observe PMU-driven dispatch counts. No scheduling impact.

---

## 4. Specific Questions

### Where is `is_smt_contended`?

**Not ported.** The C function (line 455) checks whether a CPU's SMT sibling is busy by testing it against the idle cpumask. It depends on `smt_sibling()` which reads the per-CPU `cpu_ctx->smt` kptr cpumask.

The Rust port does not have the `smt` field in `CpuCtx`, so there is no way to look up SMT siblings. The entire SMT contention avoidance path in `pick_idle_cpu()` (C lines 672-676) is skipped.

On kernel >= 6.16, `scx_bpf_select_cpu_and()` with `SCX_PICK_IDLE_CORE` provides SMT-aware idle CPU selection, partially compensating. On older kernels, there is no SMT awareness in the Rust port.

**Tracking**: PORT_TODO #1 (smt_sibling) and PORT_TODO #2 (is_smt_contended).

### Where is `cpus_share_cache`?

**Not ported.** The C function (line 494) compares LLC IDs for two CPUs using `cpu_llc_id()` from `scx/percpu.bpf.h`. The Rust port does not have access to per-CPU LLC ID data.

Used in one place: the hybrid wake-affine guard in `pick_idle_cpu()` (C line 673). The Rust port skips this guard entirely, so on hybrid systems the wakee may be unnecessarily moved to a faster core even when `prev_cpu` has a fully-idle core in the same LLC.

**Tracking**: PORT_TODO #3.

### Where is `smt_sibling`?

**Not ported.** The C function (line 432) reads `cpu_ctx->smt` (a per-CPU kptr cpumask) to find the first CPU in the sibling mask. The `smt` field is populated by the `enable_sibling_cpu` syscall program.

The Rust `CpuCtx` struct (line 111) does not have an `smt` field. The Rust port eliminated the `enable_sibling_cpu` syscall program and has no mechanism to store or look up SMT siblings.

**Tracking**: PORT_TODO #1, PORT_TODO #5.

### Where is `enable_sibling_cpu` syscall program?

**Not ported, nothing replaced it.** The C program (line 785) is a `SEC("syscall")` BPF program that userspace calls via `bpf_prog_test_run` to populate per-CPU SMT sibling cpumasks.

The Rust port eliminated all `SEC("syscall")` programs. For `enable_primary_cpu`, the replacement is a `PRIMARY_CPU_LIST` global array. For `enable_sibling_cpu`, there is no replacement -- the SMT sibling data is simply absent.

A proposed fix: add `SMT_SIBLINGS: [i32; MAX_CPUS]` global array (each entry = sibling CPU ID, or -1 for none), populated by userspace before load. This would enable reimplementation of `smt_sibling()` without needing kptr cpumasks in per-CPU maps.

**Tracking**: PORT_TODO #5.

### Where is `enable_primary_cpu` syscall program?

**Replaced by `PRIMARY_CPU_LIST` global array** (Rust line 330).

The C program (line 813) uses `bpf_prog_test_run` to call a `SEC("syscall")` program that adds CPUs to the `primary_cpumask` kptr one at a time.

The Rust replacement: userspace populates the `PRIMARY_CPU_LIST` array (terminated by -1 sentinel) before loading the BPF program. The `on_init()` function (Rust line 1912-1925) iterates this array under RCU lock and calls `cpumask::set_cpu()` for each CPU.

This is a complete replacement with equivalent functionality.

### Where is `UEI_RECORD`?

**Not ported.** `UEI_RECORD(uei, ei)` in `cosmos_exit()` (C line 1275) saves the scheduler exit information for userspace.

The Rust `on_exit()` (line 1971) is a no-op. Userspace cannot read exit reasons.

**Tracking**: PORT_TODO #10.

### Where is `is_wakeup()`?

**Inlined.** The C function (line 628) is a one-liner: `return wake_flags & SCX_WAKE_TTWU;`

In Rust, this is inlined at its single use site (line 1346):
```rust
if unsafe { PRIMARY_ALL } && (effective_wake_flags & SCX_WAKE_TTWU) != 0 {
```

No tracking needed -- this is a stylistic choice, not a gap.

### Where is `task_should_migrate()`?

**Inlined in `on_enqueue()`** at Rust line 1486:
```rust
let should_migrate = !is_running && (enq_flags & SCX_ENQ_CPU_SELECTED) == 0;
```

This matches the C logic (line 867-873):
```c
return !__COMPAT_is_enq_cpu_selected(enq_flags) && !scx_bpf_task_running(p);
```

The C version uses `__COMPAT_is_enq_cpu_selected()` which is a compat wrapper that checks `SCX_ENQ_CPU_SELECTED`. The Rust version checks the flag directly.

No tracking needed -- functionally equivalent.

---

## 5. Globals Mapping

| C Global | C Type | C Default | Rust Global | Rust Type | Rust Default | Notes |
|----------|--------|-----------|-------------|-----------|--------------|-------|
| `primary_cpumask` | `struct bpf_cpumask __kptr *` | NULL | `PRIMARY_CPUMASK` | `Kptr<bpf_cpumask>` | zeroed | Same semantics |
| `primary_all` | `const volatile bool` | `true` | `PRIMARY_ALL` | `bool` | `true` | Same |
| `flat_idle_scan` | `const volatile bool` | `false` | `FLAT_IDLE_SCAN` | `bool` | `false` | Same |
| `smt_enabled` | `const volatile bool` | `true` | `SMT_ENABLED` | `bool` | `true` | Same |
| `preferred_idle_scan` | `const volatile bool` | `false` | `PREFERRED_IDLE_SCAN` | `bool` | `false` | Same |
| `preferred_cpus` | `const volatile u64[MAX_CPUS]` | 0 | `PREFERRED_CPUS` | `[i32; MAX_CPUS]` | -1 | Different type (u64 vs i32), different default (0 vs -1 sentinel) |
| `cpu_capacity` | `const volatile u64[MAX_CPUS]` | 0 | `CPU_CAPACITY` | `[u64; MAX_CPUS]` | 0 | Same |
| `cpufreq_enabled` | `const volatile bool` | `true` | `CPUFREQ_ENABLED` | `bool` | `true` | Same |
| `numa_enabled` | `const volatile bool` | (false) | `NUMA_ENABLED` | `bool` | `false` | Same |
| `avoid_smt` | `const volatile bool` | `true` | `AVOID_SMT` | `bool` | `true` | Same |
| `mm_affinity` | `const volatile bool` | (false) | `MM_AFFINITY` | `bool` | `false` | Same |
| `perf_config` | `const volatile u64` | (0) | `PERF_CONFIG` | `u64` | 0 | Same |
| `perf_threshold` | `const volatile u64` | (0) | `PERF_THRESHOLD` | `u64` | 0 | Same |
| `deferred_wakeups` | `const volatile bool` | `true` | `DEFERRED_WAKEUPS` | `bool` | `true` | Same |
| `perf_sticky` | `const volatile bool` | (false) | `PERF_STICKY` | `bool` | `false` | Same |
| `no_wake_sync` | `const volatile bool` | (false) | `NO_WAKE_SYNC` | `bool` | `false` | Same |
| `slice_ns` | `const volatile u64` | 10000 | `SLICE_NS` | `u64` | 10000 | Same |
| `slice_lag` | `const volatile u64` | 20000000 | `SLICE_LAG` | `u64` | 20000000 | Same |
| `busy_threshold` | `const volatile u64` | (0) | `BUSY_THRESHOLD` | `u64` | 0 | Same |
| `cpu_util` | `volatile u64` | (0) | `CPU_UTIL` | `u64` | 0 | Same |
| `nr_event_dispatches` | `volatile u64` | (0) | -- | -- | -- | **NOT PORTED** (stats counter) |
| `uei` | `UEI_DEFINE(uei)` | -- | -- | -- | -- | **NOT PORTED** (UEI mechanism) |
| `nr_cpu_ids` | `static u64` | (0) | `NR_CPU_IDS` | `u32` | 0 | Different type (u64 vs u32) |
| `nr_node_ids` | `const volatile u32` | (0) | `NR_NODES` | `u32` | 1 | Different name, different default (0 vs 1) |
| `vtime_now` | `static u64` | (0) | `VTIME_NOW` | `u64` | 0 | Same |
| -- | -- | -- | `LAST_CPU` | `u32` | 0 | Rust-only: C uses `static u32 last_cpu` local to `pick_idle_cpu_pref_smt()` |
| -- | -- | -- | `CPU_TO_NODE` | `[u32; MAX_CPUS]` | [0; 1024] | Replaces C `cpu_node_map` hash map |
| -- | -- | -- | `PRIMARY_CPU_LIST` | `[i32; MAX_CPUS]` | [-1; 1024] | Replaces C `enable_primary_cpu` syscall program |

---

## 6. Map Definitions Mapping

| C Map | C Type | C Key/Value | Rust Map | Rust Type | Notes |
|-------|--------|-------------|----------|-----------|-------|
| `task_ctx_stor` | `BPF_MAP_TYPE_TASK_STORAGE` | int / `struct task_ctx` | `TASK_CTX` | `TaskStorage<TaskCtx>` | Same semantics; `BPF_F_NO_PREALLOC` set in C, assumed in Rust `TaskStorage` |
| `cpu_node_map` | `BPF_MAP_TYPE_HASH` | u32 / u32, max 1024 | `CPU_TO_NODE` | `[u32; MAX_CPUS]` global | Replaced: hash map -> flat array. Populated as global instead of via map ops |
| `cpu_ctx_stor` | `BPF_MAP_TYPE_PERCPU_ARRAY` | u32 / `struct cpu_ctx`, max 1 | `CPU_CTX` | `PerCpuArray<CpuCtx, 1>` | Same. Note: C `cpu_ctx` has `smt` kptr field; Rust `CpuCtx` does not |
| `wakeup_timer` | `BPF_MAP_TYPE_ARRAY` | u32 / `struct wakeup_timer`, max 1 | `WAKEUP_TIMER` | `BpfArray<WakeupTimer, 1>` | Same |
| -- | -- | -- | `SCX_PMU_MAP` | `PerfEventArray<1024>` | Rust-only: perf event array for tracing program PMU reads |
| -- | -- | -- | `PMU_BASELINE` | `PerCpuArray<u64, 1>` | Rust-only: per-CPU baseline counter for tracing program |

---

## 7. Struct Definitions Mapping

### `task_ctx` / `TaskCtx`

| C Field | C Type | Rust Field | Rust Type | Notes |
|---------|--------|------------|-----------|-------|
| `last_run_at` | `u64` | `last_run_at` | `u64` | Same |
| `exec_runtime` | `u64` | `exec_runtime` | `u64` | Same (different field order: C has `last_run_at` first; Rust has `exec_runtime` first) |
| `wakeup_freq` | `u64` | `wakeup_freq` | `u64` | Same |
| `last_woke_at` | `u64` | `last_woke_at` | `u64` | Same |
| `perf_events` | `u64` | `perf_events` | `u64` | Same |

Field order differs: C is `[last_run_at, exec_runtime, wakeup_freq, last_woke_at, perf_events]`; Rust is `[exec_runtime, wakeup_freq, last_run_at, last_woke_at, perf_events]`. This does not matter since each port accesses fields by name, not offset, and the struct is not shared between the two implementations.

### `cpu_ctx` / `CpuCtx`

| C Field | C Type | Rust Field | Rust Type | Notes |
|---------|--------|------------|-----------|-------|
| `last_update` | `u64` | `last_update` | `u64` | Same |
| `perf_lvl` | `u64` | `perf_lvl` | `u64` | Same |
| `perf_events` | `u64` | `perf_events` | `u64` | Same |
| `smt` | `struct bpf_cpumask __kptr *` | -- | -- | **NOT PORTED**: kptr cpumask for SMT siblings. See PORT_TODO #1, #5 |

### `wakeup_timer` / `WakeupTimer`

| C Field | C Type | Rust Field | Rust Type | Notes |
|---------|--------|------------|-----------|-------|
| `timer` | `struct bpf_timer` | `timer` | `BpfTimer` | Same |

### `domain_arg` (C only, from `intf.h`)

| C Field | C Type | Notes |
|---------|--------|-------|
| `cpu_id` | `s32` | Used by `enable_sibling_cpu` syscall program |
| `sibling_cpu_id` | `s32` | Used by `enable_sibling_cpu` syscall program |

**Not ported**: This struct is only needed for the `enable_sibling_cpu` syscall program which is not ported (PORT_TODO #5).

### `cpu_arg` (C only, from `intf.h`)

| C Field | C Type | Notes |
|---------|--------|-------|
| `cpu_id` | `s32` | Used by `enable_primary_cpu` syscall program |

**Not ported**: This struct is only needed for the `enable_primary_cpu` syscall program which was replaced by the `PRIMARY_CPU_LIST` global array.

### `LeastBusyCtx` (Rust only)

| Rust Field | Rust Type | Notes |
|------------|-----------|-------|
| `node` | `u32` | NUMA node to filter by |
| `ret_cpu` | `i32` | Best CPU found so far |
| `min` | `u64` | Minimum perf_events seen |

Rust-only struct used as context for `bpf_loop` callback. The C version uses local variables in a `bpf_for` loop instead.

---

## Summary of Gaps

### Critical gaps (affect scheduling behavior on specific hardware)

1. **SMT sibling awareness** (PORT_TODOs #1, #2, #4, #5): On SMT systems, the Rust port cannot detect SMT contention or prefer full-idle cores during flat/preferred scanning. Partially mitigated on kernel >= 6.16 by `select_cpu_and()` with `SCX_PICK_IDLE_CORE`.

2. **LLC topology** (PORT_TODO #3): On multi-LLC systems, the hybrid wake-affine guard (`cpus_share_cache`) is missing, which may cause unnecessary cross-LLC migrations on heterogeneous CPU systems.

### Minor gaps (diagnostics, rare paths)

3. **UEI_RECORD** (PORT_TODO #10): Userspace cannot read scheduler exit reasons.
4. **nr_event_dispatches counter** (PORT_TODO #12): Missing diagnostics counter.
5. **prev_cpu validation** (PORT_TODO #8): Missing `cpus_ptr` check in select_cpu, only affects cpuset changes.
6. **pick_least_busy_event_cpu** (PORT_TODO #7): Missing `is_cpu_idle` and `cpus_ptr` checks.

### Deliberate simplifications (acceptable)

7. **wakeup_timerfn is_cpu_idle check** (PORT_TODO #6): `SCX_KICK_IDLE` makes this check unnecessary.
8. **scx_pmu_uninstall** (PORT_TODO #11): Kernel handles cleanup on BPF detach.
9. **PMU architecture** (PORT_TODO #9): Tracing program approach is functionally equivalent.
