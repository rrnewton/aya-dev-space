---
title: 'scx_purerust elegance: reusable SCX library crate'
status: open
priority: 2
issue_type: task
labels:
- scx
- architecture
created_at: 2026-03-09T20:40:35.999217122+00:00
updated_at: 2026-03-10T15:05:15.166955666+00:00
---

# Description

Deferred: scx_purerust is currently the only pure-Rust scheduler. Extracting a shared crate makes sense when a second pure-Rust scheduler is written — at that point, the natural refactoring point is clear. The compat/ module is well-organized with clear boundaries (kfuncs.rs, struct_ops.rs, vmlinux.rs) making future extraction straightforward.
