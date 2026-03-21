---
title: 'P0: task_dl wrong lag_scale, clamp order, and comparison'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.153433151+00:00
updated_at: 2026-03-20T23:16:26.134900375+00:00
---

# Description

Three bugs in deadline calculation: (1) lag_scale uses slice_lag*(1+wf/1024) vs C's slice_lag*MAX(wf,1). (2) C clamps vtime then adds exec; Rust clamps deadline. (3) Unsigned < vs signed time_before. File: scx_cosmos-ebpf/src/main.rs:1184-1217
