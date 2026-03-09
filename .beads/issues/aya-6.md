---
title: 'Test -g waking: sched_waking delay'
status: closed
priority: 2
issue_type: task
created_at: 2026-02-24T23:35:31.054416737+00:00
updated_at: 2026-02-24T23:47:48.283976251+00:00
closed_at: 2026-02-24T23:47:48.283976140+00:00
---

# Description

Run rsched with -g waking. Verify: waking delay histogram (sched_waking to sched_switch) shows data. This is the most expensive tracepoint.
