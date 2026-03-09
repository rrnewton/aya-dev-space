---
title: Revert or justify bpf_map_create visibility change
status: open
priority: 2
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.100045586+00:00
updated_at: 2026-03-09T20:40:04.100045586+00:00
---

# Description

Changed pub(super) to pub(crate) as collateral. Either revert and use a dedicated struct_ops map creation function, or justify separately.
