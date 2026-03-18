---
title: 'Cosmos 100%: deferred wakeup timer'
status: closed
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.327763474+00:00
updated_at: 2026-03-18T19:53:03.486506940+00:00
---

# Description

Batch CPU wakeups using BPF timer. timer.rs module exists with init/start/cancel helpers. Integration needs: (1) BPF_MAP_TYPE_ARRAY with BpfTimer value, (2) timer callback function with #[no_mangle], (3) init() wiring, (4) enqueue() calling timer_start instead of direct kick. The timer callback is a BPF function pointer — verifier requires it as a separate non-inlined function.
