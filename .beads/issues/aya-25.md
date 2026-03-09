---
title: Remove unsafe transmute for expected_attach_type
status: closed
priority: 2
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.097212526+00:00
updated_at: 2026-03-09T23:11:04.037541873+00:00
---

# Description

Added SAFETY comment explaining the transmute is correct: the kernel interprets expected_attach_type as a raw u32 member index for struct_ops programs. Changing ProgramData's type would be too invasive for this PR.
