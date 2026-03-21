---
title: 'Cosmos port accuracy audit: C vs Rust line-by-line'
status: closed
priority: 2
issue_type: task
labels:
- audit
depends_on:
  aya-21: parent-child
created_at: 2026-03-20T22:49:52.991362386+00:00
updated_at: 2026-03-21T00:58:18.996545964+00:00
---

# Description

Cosmos port accuracy audit: C vs Rust line-by-line

## Status: AUDIT COMPLETE

5 parallel agents audited every function, global, map, struct, and constant.

## BUGS (must fix)

1. **update_freq: wrong constant and averaging** — Uses 1024*1M (should be 100*1M), uses (old+new)/2 (should be calc_avg EWMA 0.75/0.25). Corrupts wakeup_freq by ~10x.
2. **task_dl: wrong lag_scale formula** — Uses slice_lag*(1+wf/1024) vs C's slice_lag*MAX(wf,1). Completely different vtime credit clamping.
3. **task_dl: wrong clamp ordering** — C clamps vtime first, then adds exec. Rust computes deadline first, then clamps. Writes deadline back to dsq_vtime (should write clamped vtime).
4. **task_dl: unsigned < vs signed time_before** — Wrapping comparison semantics differ near u64 boundary.
5. **select_cpu_dfl from enqueue** — pick_idle_cpu called from on_enqueue reaches select_cpu_dfl, which is only valid from ops.select_cpu(). Need from_enqueue guard.
6. **Missing prev_cpu validation** — No bpf_cpumask_test_cpu(prev_cpu, p->cpus_ptr) check. May pass disallowed CPU.
7. **Hybrid wake-affine: wrong flag** — Checks SCX_WAKE_SYNC instead of SCX_WAKE_TTWU. Missing primary_all guard, LLC sharing, SMT contention checks.
8. **Hybrid wake-affine: missing prev_cpu redirection** — C sets prev_cpu=this_cpu for subsequent idle scan. Rust returns immediately or falls through without redirecting.
9. **Per-CPU init loop zeros same entry** — CPU_CTX.get_ptr_mut(0) returns current CPU, not cpu N. Loop is a no-op for all but current CPU.
10. **Extra cctx.last_update in on_running** — C only sets in stopping. Setting in running shortens delta_t.
11. **is_system_busy default** — BUSY_THRESHOLD=75 vs C's 0. Different startup behavior.

## MISSING (should port)

1. is_pcpu_task — per-CPU/migration-disabled task check in enqueue
2. task_should_migrate — missing SCX_ENQ_CPU_SELECTED check
3. pick_idle_cpu_flat 4-tier cascade (primary+SMT, primary, SMT, any)
4. pick_idle_cpu_pref_smt — cpus_ptr check, prev_cpu fast path, round-robin
5. is_system_busy guard on preferred/flat scan
6. cpus_share_cache, is_smt_contended, smt_sibling helpers
7. cpu_ctx.smt kptr field + enable_sibling_cpu syscall program
8. enable_primary_cpu syscall program
9. pick_least_busy_event_cpu (currently stub)
10. PMU event-heavy dispatch in enqueue
11. UEI_RECORD in on_exit
12. perf_sticky global
13. nr_event_dispatches counter

## MATCH (verified correct)

- calc_avg
- shared_dsq
- wakeup_cpu
- cosmos_dispatch / on_dispatch
- cosmos_enable / on_enable
- cosmos_exit_task / on_exit_task (different approach, same goal)
- SCX_OPS_DEFINE (name, timeout, callbacks, flags all match)
- All constants (MAX_CPUS, SCX_DSQ_LOCAL, SCX_KICK_IDLE, etc.)
- Most globals (slice_ns, slice_lag, perf_config, etc.)
