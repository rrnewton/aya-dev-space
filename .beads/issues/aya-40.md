---
title: 'Decide: split aya struct_ops into multiple PRs?'
status: open
priority: 2
issue_type: task
labels:
- aya
- architecture
created_at: 2026-03-09T20:40:36.002694166+00:00
updated_at: 2026-03-09T20:40:36.002694166+00:00
---

# Description

The aya changes could be split: (1) aya-obj section parsing + BTF types made public, (2) BTF sanitization fixes, (3) kfunc call relocation support, (4) StructOps program type + map handling + attachment, (5) kfunc registration API (if kept). Discuss with upstream.
