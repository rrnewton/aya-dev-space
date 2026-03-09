---
title: Fix duplicate doc comment on Btf::to_bytes()
status: open
priority: 3
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.095751288+00:00
updated_at: 2026-03-09T20:40:04.095751288+00:00
---

# Description

Two consecutive '/// Encodes the metadata as BTF format' lines.
