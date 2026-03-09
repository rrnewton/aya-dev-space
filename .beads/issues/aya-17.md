---
title: 'Test --topology: load topology from JSON file'
status: closed
priority: 2
issue_type: task
created_at: 2026-02-24T23:35:45.800852443+00:00
updated_at: 2026-02-24T23:47:48.303016225+00:00
closed_at: 2026-02-24T23:47:48.303016085+00:00
---

# Description

Run rsched with --gen-topology to produce JSON, save it, then run with --topology <file> -g migration. Verify migration output uses the loaded topology.
