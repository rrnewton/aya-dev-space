---
title: 'P1: Missing SCX_ENQ_CPU_SELECTED check'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.169699685+00:00
updated_at: 2026-03-20T23:16:26.149993288+00:00
---

# Description

task_should_migrate in C checks \!__COMPAT_is_enq_cpu_selected(enq_flags). Rust only checks \!is_running. File: on_enqueue
