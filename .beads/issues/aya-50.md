---
title: 'Cosmos 100%: migration in enqueue'
status: closed
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.331647248+00:00
updated_at: 2026-03-15T20:14:01.964416439+00:00
---

# Description

FIXED. Root cause was NOT trusted_ptr consumption (that was a misdiagnosis). The actual bug was in our inline asm kfunc wrappers: using in("r1") instead of inlateout("r1") => _. BPF calling convention clobbers R0-R5, but in() told LLVM the register was preserved, so it skipped reloading p from a callee-saved register before the second kfunc call. Fix: changed all inline asm wrappers across the entire scx-ebpf crate to use inlateout. Migration pattern (task_cpu + task_running + dsq_insert on same pointer) now works.
