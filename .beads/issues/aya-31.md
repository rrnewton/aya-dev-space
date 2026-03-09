---
title: Avoid duplicate Btf::from_sys_fs() call
status: closed
priority: 2
issue_type: task
labels:
- aya
- cleanup
depends_on:
  aya-21: parent-child
created_at: 2026-03-09T20:40:04.107683426+00:00
updated_at: 2026-03-09T23:14:52.482083025+00:00
---

# Description

Called once in EbpfLoader::new() and again inside attach_struct_ops(). Should reuse the existing kernel BTF.
