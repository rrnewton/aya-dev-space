---
title: 'Test -g migration: CPU migration tracking'
status: closed
priority: 2
issue_type: task
created_at: 2026-02-24T23:35:31.056024090+00:00
updated_at: 2026-02-24T23:47:48.285737194+00:00
closed_at: 2026-02-24T23:47:48.285737074+00:00
---

# Description

Run rsched with -g migration. Verify: per-process migration counts per second with p50/p90/p99, cross-CCX and cross-NUMA migration classification.
