---
title: 'Decide: should kfunc support be general or struct_ops-specific?'
status: open
priority: 2
issue_type: task
labels:
- aya
- architecture
created_at: 2026-03-09T20:40:36.001094909+00:00
updated_at: 2026-03-10T15:05:15.168753621+00:00
---

# Description

Decision: the kfunc call patching in aya (relocation.rs fixup + fixup_kfunc_calls vmlinux resolution) is already general-purpose. It works for any BPF program type that calls kfuncs via extern C symbols with inline asm. Document it as general kfunc support in the PR description. No API changes needed.
