---
title: 'P0: sched_ext_ops.flags missing critical flags'
status: closed
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-58: parent-child
created_at: 2026-03-20T23:05:27.161451920+00:00
updated_at: 2026-03-20T23:16:26.142639803+00:00
---

# Description

scx_ops_define\! sets no flags. C sets SCX_OPS_ENQ_EXITING | SCX_OPS_ENQ_LAST | SCX_OPS_ENQ_MIGRATION_DISABLED | SCX_OPS_ALLOW_QUEUED_WAKEUP. Without these, kernel bypasses scheduler for exiting/migration-disabled tasks. File: scx_ops_define\! macro invocation
