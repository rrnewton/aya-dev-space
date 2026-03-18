---
title: 'Cosmos fails on 6.16 kernel: verifier rejects write_volatile to task_struct.scx.dsq_vtime'
status: open
priority: 2
issue_type: task
labels:
- bug
depends_on:
  aya-33: parent-child
created_at: 2026-03-18T19:51:05.090701508+00:00
updated_at: 2026-03-18T19:51:05.090701508+00:00
---

# Description

When running cosmos on kernel 6.16.0, the BPF verifier rejects the enable callback (and likely enqueue/stopping too) because write_field_u64() uses write_volatile via raw pointer arithmetic to write to task_struct.scx.dsq_vtime. The 6.16 verifier treats the callback arg as trusted_ptr_task_struct() and rejects arbitrary u64 stores at computed offsets.

Error: 'func enable arg0 has btf_id 115 type STRUCT task_struct / R1_w=trusted_ptr_task_struct() / (7b) *(u64 *)(r1 +912) = r2'

This does NOT affect kernel 6.13 (host kernel), which passes fine. The issue is that without CO-RE field access (BTF-guided member access), the Rust eBPF code does plain pointer arithmetic, which newer verifier versions reject for trusted_ptr args.

Possible fixes:
1. Use bpf_probe_write_user() or similar helper (unlikely to work for kernel structs)
2. Wait for CO-RE support in Rust BPF (aya-42)
3. Use BPF_CORE_READ_WRITE macros equivalent (doesn't exist in Rust yet)
4. Investigate if the 6.16 verifier has a way to allowlist these writes for struct_ops

Note: cosmos built WITHOUT kernel_6_16 feature also fails on 6.16 — the issue is not related to select_cpu_and but to the fundamental write_volatile approach.
