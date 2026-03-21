---
title: 'P1: Per-CPU init loop zeros same entry'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.165801864+00:00
updated_at: 2026-03-20T23:16:26.146332675+00:00
---

# Description

on_init loop uses CPU_CTX.get_ptr_mut(0) which returns current CPU's entry, not cpu N. Zeros same entry N times. File: on_init perf_events init loop
