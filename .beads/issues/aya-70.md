---
title: 'P1: pick_idle_cpu missing is_system_busy guard and 4-tier cascade'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.171711095+00:00
updated_at: 2026-03-21T00:57:53.895106974+00:00
---

# Description

C's pick_idle_cpu_flat does 4-tier cascade (primary+SMT, primary, SMT, any) and only enters flat/preferred scan when \!is_system_busy(). Rust always enters preferred scan and does single-tier. Also missing cpus_ptr check, prev_cpu fast path, round-robin rotation. File: pick_idle_cpu, pick_idle_cpu_preferred
