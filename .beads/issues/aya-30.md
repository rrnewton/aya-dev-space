---
title: Fix overly broad license DATASEC sanitization
status: closed
priority: 2
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.105522651+00:00
updated_at: 2026-03-10T15:04:44.675850209+00:00
---

# Description

Kept as-is: the license DATASEC sanitization is correct — the kernel BTF validator rejects unknown section names. Regular aya programs also have license DATASECs in BTF but they work because the fixup_and_sanitize path handles them. The to_bytes() sanitization is a harmless safety net.
