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
updated_at: 2026-03-17T13:32:05.783523616+00:00
---

# Description

PMU tracking infrastructure implemented. PERF_CONFIG/PERF_THRESHOLD globals, TaskCtx/CpuCtx perf fields, update_perf_counters() in running/stopping, is_event_heavy() check. Remaining: PERF_EVENT_ARRAY map type + userspace perf_event_open() wiring.
