---
title: 'P0: NUMA globals never written to BPF'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.163570232+00:00
updated_at: 2026-03-20T23:16:26.144331420+00:00
---

# Description

Userspace detects NUMA topology but never writes NUMA_ENABLED, NR_NODES, CPU_TO_NODE to BPF globals. NUMA scheduling is non-functional. File: scx_cosmos/src/main.rs
