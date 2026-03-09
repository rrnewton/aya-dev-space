---
title: Remove dead register_kfunc API
status: closed
priority: 1
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.092885499+00:00
updated_at: 2026-03-09T23:10:09.120240368+00:00
---

# Description

KfuncSignature, KfuncParamType, register_kfunc(), and apply_kfunc_registrations() add FUNC entries to BTF that are immediately sanitized to INT placeholders in to_bytes(). Kfunc resolution actually uses vmlinux BTF lookup in fixup_kfunc_calls(). Either remove entirely or make it work via split BTF approach.
