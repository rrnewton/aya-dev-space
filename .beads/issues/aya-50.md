---
title: 'Cosmos 100%: migration in enqueue'
status: open
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.331647248+00:00
updated_at: 2026-03-14T18:42:36.425528612+00:00
---

# Description

UPDATED: Research (docs/trusted_ptr_analysis.md) shows the original 'trusted_ptr consumption' assumption was WRONG. The scx kfuncs are KF_RCU (not KF_RELEASE), and callee-saved registers retain PTR_TRUSTED across calls. The migration pattern (task_cpu + task_running + dsq_insert on same pointer) should work if the compiler keeps p in R6-R9. The earlier verifier failure was likely register pressure, not trust invalidation. Action: re-attempt the three-kfunc sequence in on_enqueue. If it fails again, the issue is register allocation (fixable with subprograms or different code structure), not a fundamental verifier limitation.
