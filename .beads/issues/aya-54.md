---
title: 'Cosmos 100%: flat/preferred idle scan modes'
status: closed
priority: 3
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.338244760+00:00
updated_at: 2026-03-17T13:32:05.785511560+00:00
---

# Description

Flat and preferred idle scan modes implemented. PREFERRED_CPUS[1024] sorted by capacity, pick_idle_cpu_preferred() with bounded iteration, userspace reads cpu_capacity from sysfs.
