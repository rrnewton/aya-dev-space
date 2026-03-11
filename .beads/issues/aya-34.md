---
title: Replace scx_ops_define! macro with proc macro
status: closed
priority: 2
issue_type: task
labels:
- scx
- ebpf
depends_on:
  aya-33: parent-child
created_at: 2026-03-09T20:40:21.449846274+00:00
updated_at: 2026-03-11T21:32:06.117495538+00:00
---

# Description

Implemented scx-ebpf-derive proc macro crate. The scx_ops_define! macro is now data-driven: 34 callback signatures are encoded as a const table, and the proc macro generates trampolines programmatically. Adding new callbacks requires one CallbackSig entry. Unknown callbacks produce compile-time errors.
