---
title: CO-RE post-processor prototype complete
status: open
priority: 3
issue_type: task
labels:
- aya
- core
depends_on:
  aya-33: parent-child
created_at: 2026-03-12T01:00:38.244534367+00:00
updated_at: 2026-03-12T01:00:38.244534367+00:00
---

# Description

Prototype aya-core-postprocessor built in aya2 worktree. Generates bpf_core_relo records in .BTF.ext from a sidecar TOML spec. 2068 lines, 9 passing tests. Uses sidecar file as marker mechanism; future work to integrate inline asm markers from core_read! macro.
