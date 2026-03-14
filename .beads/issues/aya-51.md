---
title: 'Cosmos 100%: mm_affinity (address space affinity)'
status: open
priority: 3
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.333411572+00:00
updated_at: 2026-03-14T14:51:26.333411572+00:00
---

# Description

When mm_affinity enabled and waker/wakee share same mm, prefer keeping them on same CPU. Needs core_read\!(task_struct, p, mm) and core_read\!(task_struct, current, mm) then comparison. Straightforward with current core_read\! macro. C reference: is_wake_affine() checks current->mm == p->mm.
