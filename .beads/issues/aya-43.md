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
updated_at: 2026-03-17T13:32:05.787073259+00:00
---

# Description

Mostly complete. Remaining: primary_cpumask (now unblocked by kptr fix), deferred timer, PMU map wiring, hybrid core migration.
