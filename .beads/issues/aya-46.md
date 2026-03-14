---
title: 'Cosmos 100%: pick_idle_cpu strategies'
status: open
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.323558054+00:00
updated_at: 2026-03-14T14:51:26.323558054+00:00
---

# Description

Port the full pick_idle_cpu() function (~200 lines in C). Strategies in order: (1) flat/preferred scan for big.LITTLE, (2) wake-affine for hybrid cores, (3) scx_bpf_select_cpu_and with primary_cpumask + avoid_smt, (4) fallback scx_bpf_select_cpu_dfl. Depends on primary_cpumask (aya-45) and SMT scanning (aya-44).
