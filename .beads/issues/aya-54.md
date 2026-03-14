---
title: 'Cosmos 100%: flat/preferred idle scan modes'
status: open
priority: 3
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.338244760+00:00
updated_at: 2026-03-14T14:51:26.338244760+00:00
---

# Description

When flat_idle_scan=true, iterate CPUs in preferred order (sorted by capacity desc) to find idle one. When preferred_idle_scan=true, use cpu_capacity array from userspace. Needs: preferred_cpus[MAX_CPUS] and cpu_capacity[MAX_CPUS] volatile arrays set by userspace. Pure logic porting, no infrastructure blockers.
