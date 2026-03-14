---
title: 'Cosmos 100%: PMU perf event integration'
status: open
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
- userspace
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.329719667+00:00
updated_at: 2026-03-14T14:51:26.329719667+00:00
---

# Description

Full PMU integration covering 4 PORT_TODOs. pmu.rs module exists with perf_event_read_value helper. Needs: (1) BPF_MAP_TYPE_PERF_EVENT_ARRAY map, (2) userspace perf_event_open() + map fd population, (3) on_running: read baseline counter, (4) on_stopping: compute delta, update per-task perf stats, (5) is_event_heavy() check, (6) pick_least_busy_event_cpu(). C reference: setup_perf_events() in userspace, scx_pmu_event_start/stop in eBPF.
