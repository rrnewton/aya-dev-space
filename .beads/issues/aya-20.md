---
title: 'Test generic perf events: -g perf=<event>'
status: closed
priority: 2
issue_type: task
created_at: 2026-02-24T23:35:45.806206462+00:00
updated_at: 2026-02-25T00:24:59.538902334+00:00
closed_at: 2026-02-25T00:24:59.538902214+00:00
---

# Description

Generic perf events (e.g. -g perf=l2-miss) load and attach but show 'No data'. NUM_GENERIC_EVENTS rodata is correctly set. IPC path works via separate hardcoded do_cpu_perf. Needs investigation of do_generic_perf BPF reads.
