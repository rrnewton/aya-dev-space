---
title: 'Cosmos 100%: PMU perf event integration'
status: closed
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
- userspace
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.329719667+00:00
updated_at: 2026-03-18T18:31:23.092369117+00:00
---

# Description

RESEARCH COMPLETE: bpf_perf_event_read_value is architecturally restricted to tracing programs. The scx PMU library already has the workaround: separate tp_btf/sched_switch and fentry/scx_tick BPF programs that read counters and share data via BPF_MAP_TYPE_TASK_STORAGE. scx_layered wires this up; scx_cosmos has a latent bug. Our Rust port needs multi-program BPF loading: tracing programs for PMU reads + struct_ops for scheduling. See docs/pmu_struct_ops_research.md.
