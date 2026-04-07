# Kptr Infrastructure Roadmap (aya-55)

## What Are Kptrs?

BPF kernel pointers (kptrs) are reference-counted pointers to kernel objects
that can be stored in BPF maps and global variables. They enable BPF programs
to hold persistent references to kernel data structures like cpumasks, cgroups,
and tasks across program invocations.

In C BPF, a kptr is declared with the `__kptr` attribute:
```c
struct bpf_cpumask __kptr *primary_cpumask;
```

The Clang compiler emits a `BTF_KIND_TYPE_TAG` with value `"kptr"` on the
pointer type. The BPF verifier reads this tag to:
1. Allow `bpf_kptr_xchg()` operations on the pointer
2. Track reference counting (acquire/release semantics)
3. Ensure the pointer is only dereferenced within RCU read-side sections

## Current State: What Works

### Global Variable Kptrs ✅ WORKING

Cosmos uses a global kptr and the kptr operations **pass BPF verification**
(verified on 176-CPU machine):

```rust
// scx_cosmos-ebpf/src/main.rs
use scx_ebpf::kptr::{Kptr, kptr_xchg, rcu_read_lock, rcu_read_unlock};

#[unsafe(no_mangle)]
static mut PRIMARY_CPUMASK: Kptr<bpf_cpumask> = Kptr::zeroed();
```

The verifier log confirms successful kptr operations:
```
call bpf_cpumask_create#80504   ; R0_w=ptr_or_null_bpf_cpumask
call bpf_kptr_xchg#194          ; R0=ptr_or_null_bpf_cpumask
call bpf_cpumask_release#80516  ;
```

### Mitosis Kptr Code ✅ PARTIALLY IMPLEMENTED

Mitosis already has significant kptr infrastructure in place:

```rust
// Already declared and working:
static mut ALL_CPUMASK: Kptr<bpf_cpumask> = Kptr::zeroed();  // line 489

struct CellCpumaskWrapper {                                     // line 444
    cpumask: Kptr<bpf_cpumask>,      // NOT a placeholder
    tmp_cpumask: Kptr<bpf_cpumask>,  // NOT a placeholder
}

bpf_map!(CELL_CPUMASKS: BpfArray<CellCpumaskWrapper, ...>);   // line 449
```

Init code (lines 1717-1759) already calls `cpumask::create()` + `kptr_xchg()`
to populate `CELL_CPUMASKS`. And `lookup_cell_cpumask()` (line 735) reads
the kptr via `Kptr::get()`. Several PORT_TODOs are stale — the declarations
exist, but the **consumer functions** are still stubbed.

### BTF Fixup Pipeline ✅ WORKING

`aya-obj` has a `fixup_kptr_types()` method (btf.rs:520-610) that:
1. Scans for `Kptr`-named structs with a single pointer member
2. Creates `PTR -> TYPE_TAG("kptr") -> STRUCT` chains
3. Rewrites `VAR` entries to point to the new chain
4. Sets `btf_value_type_id` on maps containing kptrs

This runs automatically during `to_bytes()` serialization.

### scx_ebpf APIs ✅ AVAILABLE

| API | Module | Status |
|-----|--------|--------|
| `Kptr<T>` | `scx_ebpf::kptr` | ✅ Working |
| `kptr_xchg()` | `scx_ebpf::kptr` | ✅ Working (helper #194) |
| `Kptr::get()` | `scx_ebpf::kptr` | ✅ Working (volatile read) |
| `rcu_read_lock/unlock` | `scx_ebpf::kptr` | ✅ Working |
| `cpumask::create()` | `scx_ebpf::cpumask` | ✅ Working |
| `cpumask::release()` | `scx_ebpf::cpumask` | ✅ Working |
| `cpumask::and/or/copy/...` | `scx_ebpf::cpumask` | ✅ Working |
| `BpfSpinLock` | `scx_ebpf::helpers` | ✅ Working |

## The Gap: Map-Value Kptrs in BTF

### What's Missing

`fixup_kptr_types()` Phase 3 only rewrites **VARs** (global variables), not
**STRUCT members** (fields inside map value types). When `Kptr<T>` appears as
a field inside a struct used as a BPF map value, the BTF for those members
is NOT transformed to the kernel-expected `PTR -> TYPE_TAG("kptr") -> STRUCT`
chain.

**Mitosis already has kptrs in map values** (the code compiles and the kptr
APIs are called), but the BTF emitted by the Rust compiler will look wrong
to the kernel verifier:

**Current BTF (broken for map values):**
```
STRUCT "CellCpumaskWrapper" {
    cpumask: STRUCT "Kptr" { ptr: PTR -> FWD "bpf_cpumask" }  ← verifier rejects
}
```

**Required BTF:**
```
STRUCT "CellCpumaskWrapper" {
    cpumask: PTR -> TYPE_TAG("kptr") -> STRUCT "bpf_cpumask"  ← verifier accepts
}
```

Note: This has NOT been tested at load time yet. The mitosis scheduler has
never been loaded — the kptr init code exists but may fail BTF validation.

### What Needs to Change in aya-obj

Extend `fixup_kptr_types()` Phase 3 to also rewrite **STRUCT members** (not
just VARs) that reference Kptr wrapper structs:

```rust
// Current Phase 3: only rewrites VARs
for t in &mut self.types.types {
    if let BtfType::Var(var) = t {
        // ...rewrite var.btf_type...
    }
}

// Needed: also rewrite STRUCT members
for t in &mut self.types.types {
    match t {
        BtfType::Var(var) => {
            // Existing: rewrite VAR type
            for &(kptr_struct_id, new_ptr_id) in &replacements {
                if var.btf_type == kptr_struct_id {
                    var.btf_type = new_ptr_id;
                    break;
                }
            }
        }
        BtfType::Struct(s) => {
            // NEW: rewrite STRUCT member types
            for member in &mut s.members {
                for &(kptr_struct_id, new_ptr_id) in &replacements {
                    if member.btf_type == kptr_struct_id {
                        member.btf_type = new_ptr_id;
                        // Also adjust the struct's size: Kptr<T> is 8 bytes
                        // (pointer), and the replacement is also a pointer,
                        // so no size change needed.
                        break;
                    }
                }
            }
        }
        _ => {}
    }
}
```

**This is a ~20-line change** to the existing fixup function. The infrastructure
(TYPE_TAG creation, FWD→STRUCT replacement) is already there.

### Verification Requirements

The kernel's `btf_parse_kptrs()` checks map value BTF for kptr fields.
It requires:
1. `BTF_KIND_TYPE_TAG` with string `"kptr"` wrapping the pointer target
2. The TYPE_TAG must point to a `STRUCT` or `UNION` (not FWD)
3. The struct name must match a kernel BTF type for validation

For map values, the kernel also checks that:
- The map has `btf_value_type_id` set (already handled by aya-obj)
- The kptr field offset is properly aligned (naturally satisfied by `#[repr(C)]`)
- The map supports kptrs (`BPF_MAP_TYPE_ARRAY`, `TASK_STORAGE`, etc. all do)

## PORT_TODOs: What's Stale vs What's Real

### STALE PORT_TODOs (declarations already exist — remove these):

| Line | Claim | Reality |
|------|-------|---------|
| 413 | "Missing struct cell_cpumask_wrapper" | ✅ Already declared at line 444 with `Kptr<bpf_cpumask>` fields |
| 433 | "Missing cell_cpumasks map" | ✅ Already declared at line 449 as `BpfArray<CellCpumaskWrapper>` |
| 489 | "Missing kptr globals" | ✅ `ALL_CPUMASK: Kptr<bpf_cpumask>` already at line 489 |
| 721 | "Missing lookup_cell_cpumask" | ✅ Already implemented at line 735 using `Kptr::get()` |
| 1647 | "Init cell_cpumasks" | ✅ Already implemented at lines 1717-1759 with `cpumask::create + kptr_xchg` |

### REAL PORT_TODOs: BTF fixup needed (map-value kptrs):

The code DECLARES kptrs in map values and CALLS `kptr_xchg()` on them,
but the BTF transformation for struct members hasn't been verified. This
is the `fixup_kptr_types()` gap — it may cause verifier rejection at load
time. These PORT_TODOs track real missing CONSUMER functions:

| Line | TODO | Kptr Location | What's Missing |
|------|------|---------------|----------------|
| 262 | TaskCtx cpumask_placeholder (still u64) | TASK_STORAGE | Need to change to `Kptr<bpf_cpumask>` |
| 735/781 | update_task_cpumask | TASK_STORAGE + ARRAY | Consumer function not implemented |
| 945/968/1026 | Timer kptr double-buffer swap | ARRAY value | Consumer functions not implemented |
| 1047 | recalc_cell_llc_counts with cpumask | ARRAY value | Needs cell cpumask read |

### Blocked on global kptrs (already declared, need initialization):

| Line | TODO | Status |
|------|------|--------|
| 489 | ALL_CPUMASK global: declared ✅ init'd ❌ | Need cpumask::create + set_cpu + kptr_xchg |
| 489 | ROOT_CGRP global: not declared | Need Kptr<cgroup> + cgroup::from_id |
| 1582 | Build all_cpumask from bitmap | Straightforward, no blockers |

### Transitively unblocked (need consumer functions):

| Line | TODO | Dependency |
|------|------|------------|
| 838 | pick_idle_cpu() needs task cpumask | TaskCtx.cpumask kptr |
| 1137 | recalc uses cell cpumask | cell_cpumasks map kptr |
| 1241 | update_task_cpumask for stolen task | TaskCtx.cpumask kptr |
| 1300 | update_task_llc_assignment | TaskCtx.cpumask kptr |
| 1322 | Cell-aware idle CPU selection | TaskCtx.cpumask kptr |
| 1406 | pick_idle_cpu from cell cpumask in enqueue | cell_cpumasks + TaskCtx |
| 1556 | set_cpumask: re-intersect on affinity change | TaskCtx.cpumask kptr |

**Total: 5 stale (remove) + 6 real map-value + 3 global + 7 transitive = 21 PORT_TODOs**

## Implementation Plan

### Phase 1: Extend fixup_kptr_types for STRUCT members (1-2 hours)

**File:** `aya/aya-obj/src/btf/btf.rs`

**This is the critical path.** Everything else is just writing consumer
functions that use already-available APIs.

1. Modify Phase 3 of `fixup_kptr_types()` to also scan STRUCT members
   (not just VARs) for Kptr wrapper types, and rewrite their `btf_type`
   to the `PTR -> TYPE_TAG("kptr") -> T` chain.

2. Add a test `test_fixup_kptr_types_in_struct_members()` that creates
   a STRUCT with a Kptr member and verifies the fixup rewrites it.

3. Add a test `test_fixup_kptr_types_in_nested_map_value()` that simulates
   a BPF_MAP_TYPE_ARRAY with a value struct containing kptr members.

**Estimated diff:** ~30 lines of code, ~60 lines of tests.

### Phase 2: Verify existing mitosis kptr code loads (30 min)

The mitosis scheduler already has `CellCpumaskWrapper` with `Kptr<bpf_cpumask>`
fields and init code calling `cpumask::create() + kptr_xchg()`. After Phase 1,
try loading the scheduler to verify the BTF fixup works for map values.

### Phase 3: Fix TaskCtx cpumask (1 hour)

**File:** `scx/scheds/rust_only/scx_mitosis/scx_mitosis-ebpf/src/main.rs`

1. Replace `cpumask_placeholder: u64` in TaskCtx with `cpumask: Kptr<bpf_cpumask>`
2. Update `init_task` to create per-task cpumask via `cpumask::create + kptr_xchg`
3. Implement `update_task_cpumask()` with cell/task cpumask intersection

### Phase 4: Implement consumer functions (2-3 hours)

1. Implement `update_task_cpumask()` — intersect cell + task cpumasks
2. Wire `update_task_cpumask()` into `update_task_cell()`, `set_cpumask()`
3. Implement timer callback's kptr double-buffer swap logic
4. Initialize `ALL_CPUMASK` global from `ALL_CPUS[]` bitmap
5. Implement `pick_idle_cpu()` using task cpumask kptr

### Phase 5: Clean up stale PORT_TODOs (15 min)

Remove the 5 stale PORT_TODOs that describe infrastructure that already exists.

### Phase 6: Build and test (1 hour)

1. Build with `cargo build --release` in scx_mitosis
2. Verify BTF output contains TYPE_TAG annotations for both globals and map values
3. Load on a test kernel and check verifier accepts kptr operations
4. If verifier rejects, check `fixup_kptr_types` debug output

## Risk Assessment

**Low risk** — the change is a natural extension of existing, tested code:
- `fixup_kptr_types()` already creates the correct TYPE_TAG chains
- The only change is expanding WHERE it applies them (structs, not just vars)
- Cosmos proves the kptr_xchg + cpumask pattern works at runtime
- The verifier's `btf_parse_kptrs()` handles both global and map-value kptrs

**Key question to verify:** Does the kernel's `btf_parse_kptrs()` walk into
struct members to find kptr TYPE_TAGs, or does it only check top-level types?
The C code uses kptrs in map values extensively (cell_cpumask_wrapper in MITOSIS,
task_storage in many schedulers), so this is a well-tested kernel path.

**Potential gotcha:** The struct size calculation after replacing a `Kptr<T>`
(8-byte struct wrapper) with a `PTR` (8-byte pointer) should be the same.
If there's a size mismatch, the verifier will reject the map. This should be
fine since `Kptr<T>` is `#[repr(C)]` with a single `*mut T` field.

## Summary

| What | Status | Effort |
|------|--------|--------|
| Global kptr (Kptr<T> in `static mut`) | ✅ Working | 0 (done) |
| BTF TYPE_TAG creation | ✅ Working | 0 (done) |
| fixup for VARs | ✅ Working | 0 (done) |
| **fixup for STRUCT members** | **❌ Missing** | **~30 LOC** |
| Mitosis kptr declarations | ✅ Already in code | 0 (done) |
| Mitosis kptr init (cell_cpumasks) | ✅ Already in code | 0 (done) |
| Mitosis lookup_cell_cpumask | ✅ Already in code | 0 (done) |
| TaskCtx cpumask field | ❌ Still u64 placeholder | ~20 LOC |
| update_task_cpumask consumer | ❌ Not implemented | ~60 LOC |
| Timer double-buffer swap | ❌ Stubbed | ~40 LOC |
| ALL_CPUMASK init | ❌ Not initialized | ~15 LOC |
| pick_idle_cpu consumer | ❌ Stubbed | ~50 LOC |
| Stale PORT_TODO cleanup | ❌ Need removal | 5 deletions |
| **Total PORT_TODOs addressed** | **21** | **~5 hours** |
