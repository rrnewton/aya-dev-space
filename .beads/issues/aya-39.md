---
title: 'Decide: should kfunc support be general or struct_ops-specific?'
status: open
priority: 2
issue_type: task
labels:
- aya
- architecture
created_at: 2026-03-09T20:40:36.001094909+00:00
updated_at: 2026-03-09T20:40:36.001094909+00:00
---

# Description

Other BPF program types (tracing, XDP, TC) can also call kfuncs. The current implementation only handles kfuncs in the context of struct_ops. A general solution would benefit more users. Discuss with aya upstream.
