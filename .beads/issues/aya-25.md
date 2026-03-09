---
title: Remove unsafe transmute for expected_attach_type
status: open
priority: 2
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.097212526+00:00
updated_at: 2026-03-09T20:40:04.097212526+00:00
---

# Description

In attach_struct_ops, member index is cast to bpf_attach_type via core::mem::transmute. ProgramData should accept a raw u32 for expected_attach_type.
