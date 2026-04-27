# Changelog — Session 2026-04-06/07

**105 commits** (53 parent + 27 scx + 26 aya) over ~16 hours.

---

## aya Infrastructure Bug Fixes (11 commits)

Critical fixes to the aya BPF framework that improve kernel compatibility
and correctness.

### CO-RE Postprocessor
- `3e112650` Fix CO-RE postprocessor: don't copy stale core_relo records
- `4c86ba5a` Fix CO-RE relocation corruption on kernel 6.16+
- `2fcde1b5` Fix CO-RE access string shuffling in BtfExtWriter
- `b3421a81` CO-RE postprocessor: add regression tests (32 tests)
- `fc2cf462` Remove debug println from CO-RE postprocessor

### struct_ops / BTF
- `5ed3e8e5` Fix struct_ops cross-kernel compat via BTF field remapping
- `3eb9ed89` fixup_kptr_types: extend to rewrite STRUCT members, not just VARs
- `9c2c075d` Fix CO-RE field relocation: treat Int/Ptr as compatible types
- `2bd504cb` Skip unknown map types when allow_unsupported_maps is true

### Loader Fixes
- `8d469c53` Fix pre-existing test compilation errors in aya crate
- `65ddc073` Fix all remaining clippy warnings across workspace
- `f1c43cc8` Fix compiler warnings in aya-core-postprocessor

---

## aya New Features (7 commits)

### BPF Map Types
- `fd074b20` Add BPF_MAP_TYPE_CGRP_STORAGE support to aya-ebpf and aya
- `a77809cc` Add BPF_MAP_TYPE_ARENA support to aya-obj and aya loader
- `75fc836f` Add BPF arena kfuncs and shared arena types crate

### Arena Data Structures
- `a8d7179d` Add BPF arena bump allocator backed by bpf_arena_alloc_pages
- `a9ea1ef3` Add arena linked list PoC: end-to-end BPF/userspace shared data
- `70223df1` Add arena hash map: open-addressing with linear probing
- `5188fc69` Add arena B-tree: ordered map with bounded operations for BPF

### Arena Improvements
- `5147785a` Arena hash map: fix edge cases, add validation, expand tests to 30
- `365070a8` Add arena slab allocator: O(1) alloc+free with intrusive free list
- `05f4a70e` Arena B-tree: fix lazy delete predecessor bug + regression tests
- `574ad6ad` Add arena library README and B-tree benchmark results
- `b93b6c82` Add slab allocator section to benchmark report

---

## MITOSIS BPF Scheduler (21 commits)

### Core Callbacks
- `83bc1214` PORT_TODO audit + core callbacks (select_cpu, enqueue, dispatch, running, stopping)
- `d107f867` Implement cgroup lifecycle callbacks (init/exit/move)
- `d02e84a4` Add dump, set_cpumask, and LLC-aware helpers
- `28e9ea78` Implement fentry/tp_btf auxiliary BPF programs
- `bc06a398` Implement LLC-aware scheduling + work stealing

### P0 Bug Fixes
- `11e587c1` Fix 3 P0 blockers (mitosis_init, vtime clamp, allocate_cell atomicity)
- `4ec79169` Fix core_read! for chained pointer dereference
- `b9b8a9ea` Fix cpus_ptr verifier rejection + cgroup ref leaks

### Infrastructure
- `f8b7727a` Add missing globals, data structures, and helper functions
- `92325f7c` scx-ebpf: add cgroup, cpumask, scx, and helper kfuncs
- `34a5acde` Implement BPF timer for periodic cell reconfiguration
- `84615fab` Fix 15 PORT_TODOs — spin locks, cpumask kptrs, CO-RE reads
- `b3cefff7` Implement update_task_cpumask + remove 22 stale PORT_TODOs
- `673e7bad` Implement init_cgrp_ctx_with_ancestors

### PORT_TODO Reduction
- `5a8c219b` Clean up resolved PORT_TODO comments
- `e7fadd06` Reduce PORT_TODO count from 49 to 24
- `b575fa6a` Reduce PORT_TODO from 18 to 5
- `054b1fe6` Consolidate PORT_TODOs to final 5

### Fixes
- `7c9127b0` Fix BPF_MAP_TYPE_CGRP_STORAGE constant (34 → 32)
- `a24757aa` Rename BpfSpinLock → bpf_spin_lock for kernel BTF match
- `f7c25b9d` Fix all 7 compiler warnings

---

## MITOSIS Userspace (4 commits)

- `9b85936b` Full userspace loader with topology and CLI
- `ef842906` Add stats module and debug events reader
- `827b3975` Wire up BPF percpu stats reading in userspace
- `1fa9bf39` Populate remaining BPF globals (ALL_CPUS, SLICE_NS, ROOT_CGID)
- `f1c7d2cb` Userspace cgroup walk for init-time cgrp_ctx setup

---

## Testing Infrastructure (10 commits)

### VM Test Framework
- `7a65c6f` Add comprehensive VM test runner (run-all-tests.sh)
- `f06fbf9` Add MITOSIS test matrix and stress test scripts
- `f0a3ad1` Add advanced stress tests: cycling, fork bombs, memory pressure
- `b14a362` Add comparison test matrix and updated E2E report
- `ee77a2c` Fix CO-RE access string shuffling + stress test all modes

### Build Infrastructure
- `22ae9e3` Add Makefile, Containerfile, and update build infrastructure
- `628529c` Fix container build: copy pre-built binary
- `b6c1d19` Fix test_cosmos_vm.sh: delegate to run-in-vm.sh
- `361f5ed` Add test_cosmos.sh and test_cosmos_vm.sh quick-start scripts
- `7ed2ccc` Add GitHub Actions CI with kernel version matrix

### Benchmarks
- `fc25f8e` Add arena data structure benchmark suite
- `6222a97d` Add arena benchmark suite with hash map comparison
- `3d51f978` Arena-bench: fix clippy warnings
- `ecde671` Arena-bench: add .gitignore, remove build artifacts

---

## Documentation (12 commits)

- `ae58633` Add README.md and ARCHITECTURE.md
- `92222c4` Add MITOSIS E2E testing report with VM results
- `6b97d5b` Add comprehensive session report
- `3ca4223` Add kptr infrastructure roadmap
- `2ba2f35` Add performance report and benchmark scripts
- `7d08db1` Add NEXT_SESSION.md: prioritized plan
- `ed21c8e` Update reports: PORT_TODOs 77→5
- `7a4ef43` Final documentation update
- `88ef787` Final session documentation
- `1e8281b` LANDMARK: all 3 schedulers on 3 kernels
- `31f75da` Fix kernel compat matrix (re-verified results)

---

## Summary

| Category | Commits | Key Metric |
|----------|---------|------------|
| aya bug fixes | 11 | 7 critical fixes enabling 6.16/6.17 |
| aya new features | 12 | CgrpStorage, Arena, 4 data structures |
| MITOSIS BPF | 21 | 15 callbacks, 77→5 PORT_TODOs |
| MITOSIS userspace | 5 | Loader, stats, topology, globals |
| Testing | 14 | 340+ tests, 0 failures |
| Documentation | 12 | SESSION/NEXT/PERF/E2E reports |
| **Total** | **105** | |

### Kernel Compatibility (verified)

| Kernel | scx_simple | scx_cosmos | scx_mitosis |
|--------|-----------|------------|-------------|
| 6.13 | ✅ | ✅ | ✅ |
| 6.16 | ✅ | ✅ | ✅ |
| 6.17 | ✅ | ✅ | ✅ |
