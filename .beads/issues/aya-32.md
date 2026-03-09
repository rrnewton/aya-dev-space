---
title: Split attach_struct_ops into smaller methods
status: open
priority: 2
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.109039976+00:00
updated_at: 2026-03-09T20:40:04.109039976+00:00
---

# Description

~200-line method that loads programs, creates maps, builds value buffers, and attaches. Should be decomposed.
