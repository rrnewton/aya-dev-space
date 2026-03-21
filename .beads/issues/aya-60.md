---
title: 'P0: update_freq wrong constant and averaging'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.151250973+00:00
updated_at: 2026-03-20T23:16:26.133068236+00:00
---

# Description

BPF update_freq uses 1024*1M (should be 100*1M = 100,000,000) and (old+new)/2 (should be calc_avg EWMA 0.75/0.25). Corrupts wakeup_freq by ~10x. File: scx_cosmos-ebpf/src/main.rs:594
