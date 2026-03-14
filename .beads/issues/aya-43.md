---
title: 'Implement cosmos PORT_TODOs: userspace globals + idle scanning + cpufreq'
status: open
priority: 1
issue_type: task
labels:
- scx
- cosmos
depends_on:
  aya-33: parent-child
created_at: 2026-03-13T18:15:37.428925241+00:00
updated_at: 2026-03-14T14:51:26.318281416+00:00
---

# Description

Partially complete. Implemented: userspace globals (SLICE_NS, BUSY_THRESHOLD, etc.), is_system_busy with cpu_util polling, no_wake_sync, cpufreq scaling (update_cpu_load + update_cpufreq with EWMA). Remaining: 13 PORT_TODOs covering SMT scanning, NUMA, PMU, migration, primary_cpumask, pick_idle_cpu strategies.
