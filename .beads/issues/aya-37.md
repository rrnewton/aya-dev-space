---
title: Auto-generate sched_ext_ops struct definition
status: closed
priority: 2
issue_type: task
labels:
- scx
- ebpf
depends_on:
  aya-33: parent-child
created_at: 2026-03-09T20:40:21.455523822+00:00
updated_at: 2026-03-11T20:01:25.022020661+00:00
---

# Description

sched_ext_ops is still manually defined in scx-ebpf for now, but scx-vmlinux can generate it. The manual definition is kept because the scx_ops_define\! macro needs the specific Option<fn> field types, which don't match the raw BTF output.
