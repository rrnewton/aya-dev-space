---
title: Remove unused Object.kfunc_btf_ids field
status: open
priority: 2
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.094329340+00:00
updated_at: 2026-03-09T20:40:04.094329340+00:00
---

# Description

Populated in fixup_and_sanitize_btf but never read. fixup_kfunc_calls resolves against vmlinux directly.
