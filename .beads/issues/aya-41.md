---
title: Investigate enabling LLVM BPFAbstractMemberAccess pass in rustc
status: open
priority: 3
issue_type: task
labels:
- aya
- compiler
- core
depends_on:
  aya-33: parent-child
created_at: 2026-03-11T19:55:09.818847114+00:00
updated_at: 2026-03-22T00:04:44.712313022+00:00
---

# Description

Key finding: BPFAbstractMemberAccessPass is already in libLLVM.so (it's a BPF target FunctionPass, not a clang-only pass). Rustc links the same libLLVM. The pass just isn't registered in rustc's pipeline. Two viable approaches: (1) A ~50-line LLVM plugin .so that registers the existing pass, loaded via rustc -Z llvm-plugins=libbpf_passes.so. (2) A rustc PR adding the pass to the BPF target pipeline. Both would give Rust BPF native CO-RE support with zero overhead, using the same codegen path as clang.

# Notes

Label: improvement. Research complete (docs/llvm_bpf_core_research.md). CO-RE postprocessor is the working alternative.
