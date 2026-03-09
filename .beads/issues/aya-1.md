---
title: 'Test -g latency: scheduling delay histograms and per-CPU latency'
status: closed
priority: 2
issue_type: task
created_at: 2026-02-24T23:35:31.046039262+00:00
updated_at: 2026-02-24T23:36:00.138734598+00:00
closed_at: 2026-02-24T23:36:00.138734488+00:00
---

# Description

Run rsched with -g latency (default). Verify: collapsed scheduling delays with p50/p90/p99, per-CPU scheduling delays, and runqueue depth statistics (nr_running at wakeup) all show data.
