---
title: 'aya bug: fixup_kfunc_calls fails for BPF subprograms'
status: closed
priority: 1
issue_type: task
labels:
- aya
- bug
created_at: 2026-03-16T18:02:11.295276166+00:00
updated_at: 2026-03-18T19:11:29.511606591+00:00
---

# Description

When #[inline(never)] creates a BPF subprogram, aya's fixup_kfunc_calls() in obj.rs cannot resolve kfunc imm fields because it uses original section offsets to look up relocations. After function linking (relocate_calls), subprogram instructions are appended to the main function at new offsets, but the relocation table still has the original offsets. This means kfunc calls in subprograms get imm=0, causing 'invalid kernel function call not eliminated in verifier pass'. Workaround: use #[inline(always)]. Fix: fixup_kfunc_calls needs to account for instruction offset changes during function linking.
