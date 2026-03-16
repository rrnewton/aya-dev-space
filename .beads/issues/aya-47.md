---
title: 'Cosmos 100%: NUMA per-node DSQs'
status: closed
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.325729953+00:00
updated_at: 2026-03-16T18:02:11.300510664+00:00
---

# Description

NUMA per-node DSQs implemented. CPU_TO_NODE[1024] array, shared_dsq() helper, per-node DSQ creation in init, routing in enqueue/dispatch.
