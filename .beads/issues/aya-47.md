---
title: 'Cosmos 100%: NUMA per-node DSQs'
status: open
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.325729953+00:00
updated_at: 2026-03-14T14:51:26.325729953+00:00
---

# Description

When numa_enabled, create per-node DSQs and route tasks to their node's DSQ. Needs: (1) cpu_node_map BPF hash map populated by userspace from /sys/devices/system/node/, (2) shared_dsq(cpu) helper that looks up the node, (3) init() loop creating DSQs per node. Implementable with current maps.rs infrastructure.
