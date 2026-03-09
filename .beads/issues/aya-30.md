---
title: Fix overly broad license DATASEC sanitization
status: open
priority: 2
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.105522651+00:00
updated_at: 2026-03-09T20:40:04.105522651+00:00
---

# Description

Replacing ALL license DATASECs with INT in to_bytes() could break non-struct_ops programs. Should be more targeted.
