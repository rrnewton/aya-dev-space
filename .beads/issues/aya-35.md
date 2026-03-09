---
title: Eliminate inline asm kfunc wrappers
status: open
priority: 2
issue_type: task
labels:
- scx
- ebpf
- compiler
depends_on:
  aya-33: parent-child
created_at: 2026-03-09T20:40:21.451984624+00:00
updated_at: 2026-03-09T20:40:21.451984624+00:00
---

# Description

The Rust BPF compiler emits broken call sequences for extern C kfunc declarations. Current workaround: 78 lines of inline assembly. Fix requires Rust BPF backend generating BPF_PSEUDO_KFUNC_CALL for extern fns, or an aya-ebpf #[kfunc] attribute macro.
