---
title: 'P0: select_cpu_dfl called from enqueue context'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.155334916+00:00
updated_at: 2026-03-20T23:16:26.136848139+00:00
---

# Description

pick_idle_cpu called from on_enqueue reaches select_cpu_dfl which is only valid from ops.select_cpu(). C returns -EBUSY when from_enqueue=true. Add from_enqueue parameter. File: scx_cosmos-ebpf/src/main.rs pick_idle_cpu + on_enqueue
