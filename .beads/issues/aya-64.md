---
title: 'P0: Hybrid wake-affine uses wrong flag and missing guards'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.159122320+00:00
updated_at: 2026-03-20T23:16:26.140710177+00:00
---

# Description

Checks SCX_WAKE_SYNC instead of SCX_WAKE_TTWU. Missing primary_all guard, cpus_share_cache check, is_smt_contended check, prev_cpu redirection to faster core. File: on_select_cpu lines 1030-1040
