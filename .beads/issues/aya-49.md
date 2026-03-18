---
title: 'Cosmos 100%: PMU perf event integration'
status: closed
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
- userspace
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.329719667+00:00
updated_at: 2026-03-18T15:29:33.503308374+00:00
---

# Description

CLOSED: PMU helper #55 is not available in struct_ops programs. Same limitation exists in C cosmos. The intended fix uses separate tracing programs (tp_btf/sched_switch) sharing data via maps, but this isn't wired up in either implementation. PMU code cleaned up, scheduler runs cleanly.
