---
title: 'Cosmos 100%: SMT-aware idle CPU scanning'
status: open
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.320395368+00:00
updated_at: 2026-03-14T14:51:26.320395368+00:00
---

# Description

select_cpu should use get_idle_smtmask() to prefer fully-idle cores when avoid_smt is enabled. Blocked by LLVM BPF register allocation: get_idle_smtmask() returns a reference that must survive across test_cpu(), but all callee-saved registers (r6-r9) are occupied. Workaround: use scx_bpf_select_cpu_and() with SCX_PICK_IDLE_CORE flag instead.
