---
title: 'P1: Missing is_pcpu_task check in enqueue'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.167684850+00:00
updated_at: 2026-03-20T23:16:26.148118595+00:00
---

# Description

C checks is_pcpu_task(p) (nr_cpus_allowed==1 || migration_disabled) before migration. Rust always attempts full idle scan. File: on_enqueue
