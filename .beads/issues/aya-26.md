---
title: Clean up unused struct_size variable
status: closed
priority: 3
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.098732322+00:00
updated_at: 2026-03-09T23:10:09.125308984+00:00
---

# Description

After adding wrapper_size, struct_size is still bound but only used indirectly through members. Clean up.
