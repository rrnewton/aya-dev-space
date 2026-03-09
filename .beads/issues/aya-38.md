---
title: 'scx_purerust elegance: reusable SCX library crate'
status: open
priority: 2
issue_type: task
labels:
- scx
- architecture
created_at: 2026-03-09T20:40:35.999217122+00:00
updated_at: 2026-03-09T20:40:35.999217122+00:00
---

# Description

Extract compat/ module into a standalone scx-ebpf crate (or aya-sched-ext) that provides: auto-generated sched_ext_ops struct from vmlinux BTF, scx_ops_define! proc macro, type-safe kfunc wrappers for scx_bpf_* functions. Multiple schedulers can share it.
