---
title: 'P0: SLICE_LAG 1000x too small (20us vs 20ms)'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.149181215+00:00
updated_at: 2026-03-20T23:16:26.130935252+00:00
---

# Description

Userspace computes SLICE_LAG as (slice_us * 2000).min(20M) = 20,000 ns = 20us. C cosmos uses independent --slice-lag-us default 20000, giving 20,000,000 ns = 20ms. Fix: add --slice-lag-us CLI arg with default 20000, compute as slice_lag_us * 1000. File: scx_cosmos/src/main.rs:906
