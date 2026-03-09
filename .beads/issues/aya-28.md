---
title: Fix overly broad define_link_wrapper! macro change
status: closed
priority: 2
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.101607727+00:00
updated_at: 2026-03-09T23:10:09.127043705+00:00
---

# Description

Making new() pub(crate) + #[allow(private_interfaces)] affects ALL link wrapper types. Find a targeted solution for StructOpsLink only.
