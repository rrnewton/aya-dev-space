---
title: 'Cosmos 100%: primary_cpumask with kptr'
status: open
priority: 2
issue_type: task
labels:
- cosmos
- ebpf
depends_on:
  aya-43: parent-child
created_at: 2026-03-14T14:51:26.322010126+00:00
updated_at: 2026-03-14T14:51:26.322010126+00:00
---

# Description

Implement primary_cpumask for preferred CPU domain. Requires BTF_KIND_TYPE_TAG 'kptr' which rustc doesn't emit. kptr.rs module exists with Kptr<T> wrapper + kptr_xchg + rcu_read_lock/unlock. Blocked until aya-core-postprocessor can inject TYPE_TAG into BTF, OR the LLVM plugin approach works. C reference: private(COSMOS) struct bpf_cpumask __kptr *primary_cpumask.
