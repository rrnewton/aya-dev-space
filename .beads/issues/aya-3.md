---
title: 'Test -g sleep: sleep duration and CPU idle'
status: closed
priority: 2
issue_type: task
created_at: 2026-02-24T23:35:31.049650434+00:00
updated_at: 2026-02-24T23:47:48.278402350+00:00
closed_at: 2026-02-24T23:47:48.278402240+00:00
---

# Description

Run rsched with -g sleep. Verify: collapsed sleep duration statistics (time between sched_switch and sched_wakeup) and per-CPU idle duration histograms both show data.
