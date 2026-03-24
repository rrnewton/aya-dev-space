---
title: 'Decide: split aya struct_ops into multiple PRs?'
status: closed
priority: 2
issue_type: task
labels:
- aya
- architecture
created_at: 2026-03-09T20:40:36.002694166+00:00
updated_at: 2026-03-21T23:59:18.810758418+00:00
---

# Description

Decision: split into 3 PRs for aya upstream: (1) aya-obj parsing + BTF public API changes + BTF sanitization, (2) kfunc call relocation support, (3) StructOps program type + map + attach. The eBPF-side code stays in scx repo.
