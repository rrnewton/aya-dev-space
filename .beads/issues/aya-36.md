---
title: Auto-generate vmlinux type stubs
status: open
priority: 2
issue_type: task
labels:
- scx
- ebpf
depends_on:
  aya-33: parent-child
created_at: 2026-03-09T20:40:21.453831094+00:00
updated_at: 2026-03-09T20:40:21.453831094+00:00
---

# Description

Manual task_struct { _opaque: i32 } stubs (19 lines). Should be auto-generated from vmlinux BTF using aya-gen or equivalent.
