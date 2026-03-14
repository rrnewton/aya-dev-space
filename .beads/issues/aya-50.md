---
title: 'Cosmos 100%: migration in enqueue'
status: open
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.331647248+00:00
updated_at: 2026-03-14T14:51:26.331647248+00:00
---

# Description

When task_should_migrate (ops.select_cpu not called, task not running), find idle CPU via pick_idle_cpu and dispatch via SCX_DSQ_LOCAL_ON. Blocked by BPF verifier: kfunc calls (task_cpu, task_running) consume trusted_ptr, preventing subsequent kfunc calls on same pointer. C pattern: if (task_should_migrate) { cpu = pick_idle_cpu(); dsq_insert(LOCAL_ON|cpu); wakeup_cpu(cpu); }. Possible workaround: BPF RCU read lock or separate subprogram.
