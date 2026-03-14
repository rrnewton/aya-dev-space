---
title: 'Cosmos 100%: userspace topology + stats'
status: open
priority: 2
issue_type: task
labels:
- cosmos
- userspace
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.336676402+00:00
updated_at: 2026-03-14T14:51:26.336676402+00:00
---

# Description

C cosmos userspace has: (1) Topology detection (CPU capacity, preferred CPUs, NUMA nodes) via scx_utils::Topology, (2) primary CPU detection from sysfs energy_performance_preference, (3) stats server with Metrics struct, (4) --stats CLI option. Our userspace has basic CLI + cpu_util polling but no topology or stats.
