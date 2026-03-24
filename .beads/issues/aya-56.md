---
title: 'Cosmos fails on 6.16 kernel: verifier rejects write_volatile to task_struct.scx.dsq_vtime'
status: open
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-33: parent-child
created_at: 2026-03-18T19:51:05.090701508+00:00
updated_at: 2026-03-22T00:36:43.261632019+00:00
---

# Description

Cosmos on kernels with shifted sched_ext_entity layout.

CO-RE infrastructure works (markers, postprocessor, BTF.ext records).
Kfunc setters work on 6.18 (task_set_dsq_vtime/task_set_slice).

Two remaining blockers on 6.18:
1. Verifier complexity: enqueue exceeds 1M insns due to inlined pick_idle_cpu_preferred loop. Need to make it a subprogram.
2. CO-RE type mismatch: postprocessor uses __u64 placeholder for all fields, but flags is u32. Need actual vmlinux field types.

core_write! is rejected on 6.18 — kfuncs mandatory (kernel_6_16 feature required).
