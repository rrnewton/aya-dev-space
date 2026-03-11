---
title: Auto-generate vmlinux type stubs
status: closed
priority: 2
issue_type: task
labels:
- scx
- ebpf
depends_on:
  aya-33: parent-child
created_at: 2026-03-09T20:40:21.453831094+00:00
updated_at: 2026-03-11T20:01:25.019907618+00:00
---

# Description

Implemented scx-vmlinux crate that generates Rust struct bindings from vmlinux BTF at build time using bpftool + bindgen. Produces real task_struct, sched_ext_entity etc with correct field layouts.
