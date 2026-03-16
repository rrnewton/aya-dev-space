---
title: 'Cosmos 100%: pick_idle_cpu strategies'
status: closed
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.323558054+00:00
updated_at: 2026-03-16T18:02:11.298779679+00:00
---

# Description

pick_idle_cpu implemented: select_cpu_dfl + SMT sibling verification. mm_affinity via is_wake_affine. primary_cpumask filtering deferred (needs kptr BTF TYPE_TAG).
