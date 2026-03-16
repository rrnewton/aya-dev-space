---
title: 'Cosmos 100%: SMT-aware idle CPU scanning'
status: closed
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.320395368+00:00
updated_at: 2026-03-16T18:02:11.297127072+00:00
---

# Description

SMT-aware idle scanning implemented with get_idle_smtmask + test_cpu + put_cpumask. The inline asm clobber fix (inlateout) was the key unblock. Uses #[inline(always)] due to aya subprogram kfunc resolution bug (aya-55).
