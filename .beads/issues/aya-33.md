---
title: eBPF-side struct_ops hackiness (compiler limitations)
status: open
priority: 2
issue_type: task
labels:
- scx
- ebpf
created_at: 2026-03-09T20:40:21.447938792+00:00
updated_at: 2026-03-10T15:05:24.988357923+00:00
---

# Description

These are Rust BPF compiler limitations, not aya loader bugs. They require either: (1) rustc/LLVM BPF backend fixes for kfunc codegen, or (2) aya-ebpf proc macros for struct_ops boilerplate. Both are multi-week efforts and should be tracked separately from the aya struct_ops PR.
