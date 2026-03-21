---
title: 'P1: No UEI exit detection in userspace'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.177273061+00:00
updated_at: 2026-03-21T00:55:41.696371470+00:00
---

# Description

Main loop never checks if BPF scheduler was detached. Scheduler continues polling after kernel takes over. Need uei_exited equivalent. File: scx_cosmos/src/main.rs main loop
