---
title: 'Cosmos 100%: exit_task callback'
status: open
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.335046070+00:00
updated_at: 2026-03-14T14:51:26.335046070+00:00
---

# Description

Missing exit_task callback. C cosmos cleans up per-task storage. Our TaskStorage auto-frees on task exit, but we should still register the callback for completeness. Also need to add exit_task to scx_ops_define\! proc macro CALLBACKS table if not present.
