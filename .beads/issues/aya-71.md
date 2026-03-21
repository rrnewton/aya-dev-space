---
title: 'P1: Extra cctx.last_update in on_running'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.173696356+00:00
updated_at: 2026-03-20T23:16:26.151737745+00:00
---

# Description

Rust sets cctx.last_update=now in on_running AND on_stopping. C only sets it in stopping (via update_cpu_load). Setting it in running shortens delta_t for cpufreq. File: on_running line 1317
