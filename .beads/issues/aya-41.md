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
updated_at: 2026-03-11T19:55:09.818847114+00:00
---

# Description

The LLVM BPF backend has a BPFAbstractMemberAccess pass that lowers llvm.preserve.struct.access.index intrinsics into CO-RE relocation records. Clang runs this pass but rustc does not. Enabling it for the bpfel-unknown-none target in rustc_codegen_llvm would give Rust BPF programs native CO-RE support with zero overhead. Small rustc change but requires upstream coordination. The register_tool feature (nightly) could provide the #[bpf::preserve_access_index] attribute that triggers the intrinsic emission.
