---
title: Replace scx_ops_define! macro with proc macro
status: open
priority: 2
issue_type: task
labels:
- scx
- ebpf
depends_on:
  aya-33: parent-child
created_at: 2026-03-09T20:40:21.449846274+00:00
updated_at: 2026-03-09T20:40:21.449846274+00:00
---

# Description

The scx_ops_define! macro (278 lines) manually defines every callback trampoline. Should be replaced by a proc macro that reads the kernel struct definition from vmlinux BTF and auto-generates trampolines. Belongs in aya-ebpf or a dedicated aya-sched-ext crate.
