---
title: Revert or justify bpf_map_create visibility change
status: closed
priority: 2
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.100045586+00:00
updated_at: 2026-03-09T23:10:19.484198771+00:00
---

# Description

Justified: bpf_map_create needs pub(crate) visibility because struct_ops map creation in bpf.rs (crate root) calls it via crate::sys::bpf_map_create. pub(super) is insufficient. The change is minimal and correctly scoped.
