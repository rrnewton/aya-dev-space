---
title: 'P0: Missing prev_cpu validation in select_cpu'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.157296430+00:00
updated_at: 2026-03-20T23:16:26.138627048+00:00
---

# Description

C validates prev_cpu against p->cpus_ptr and adjusts if not allowed. Rust passes unchecked prev_cpu. Add: if \!test_cpu(prev_cpu, cpus_ptr) { prev_cpu = this_cpu or first_cpu }. File: on_select_cpu
