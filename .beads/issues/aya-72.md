---
title: 'P1: is_system_busy default threshold 75 vs C''s 0'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.175550948+00:00
updated_at: 2026-03-20T23:16:26.153731809+00:00
---

# Description

BUSY_THRESHOLD defaults to 75 in Rust vs 0 in C. Also Rust adds DSQ depth fallback when CPU_UTIL==0. Different startup behavior. File: is_system_busy + BUSY_THRESHOLD
