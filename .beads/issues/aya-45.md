---
title: 'Cosmos 100%: primary_cpumask with kptr'
status: closed
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.322010126+00:00
updated_at: 2026-03-17T13:30:04.050883828+00:00
---

# Description

FIXED. Implemented fixup_kptr_types() in aya-obj/src/btf/btf.rs that detects Kptr<T> wrapper structs in BTF and rewrites the type chain from VAR -> STRUCT Kptr -> PTR -> T to VAR -> PTR -> TYPE_TAG(kptr) -> T. Called during fixup_and_sanitize_btf(). 4 new tests, 99 total passing. Merged to aya-scx.v2 at a413c0ea.
