---
title: Auto-generate sched_ext_ops struct definition
status: open
priority: 2
issue_type: task
labels:
- scx
- ebpf
depends_on:
  aya-33: parent-child
created_at: 2026-03-09T20:40:21.455523822+00:00
updated_at: 2026-03-09T20:40:21.455523822+00:00
---

# Description

Manual 72-line struct mirroring kernel's 40 fields. Must be kept in sync with kernel changes. Should be auto-generated from vmlinux BTF.
