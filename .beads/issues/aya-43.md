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
updated_at: 2026-03-13T18:15:37.428925241+00:00
---

# Description

Working on 21 PORT_TODOs in the Rust cosmos port. Priority items: userspace-configurable globals, is_system_busy with cpu_util, SMT-aware idle scanning, cpufreq integration, deferred wakeup timer.
