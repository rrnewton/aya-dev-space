# Research: Enabling LLVM BPFAbstractMemberAccess for Rust BPF CO-RE

Date: 2026-03-20

## Executive Summary

CO-RE (Compile Once Run Everywhere) field access from Rust BPF programs is
**not currently possible** but is **theoretically achievable** with compiler
modifications. The LLVM pass infrastructure is in place and runs
unconditionally for BPF targets. The blockers are all on the Rust/frontend
side: Rust cannot emit the LLVM intrinsics with required attributes, and
Rust's codegen emits byte-offset GEPs rather than struct-aware GEPs.

## 1. Is BPFAbstractMemberAccess enabled in the BPF LLVM backend?

**YES -- unconditionally.**

Verified experimentally with LLVM 21.1.7 (system) and LLVM 22.1.0 (nightly
rustc). When any IR is compiled with `-mtriple=bpfel` through `opt
-passes='default<O2>'`, the following BPF-specific passes run automatically:

```
Running pass: BPFPreserveStaticOffsetPass
Running pass: BPFAbstractMemberAccessPass    <-- the CO-RE pass
Running pass: BPFPreserveDITypePass
Running pass: BPFIRPeepholePass
Running pass: BPFAdjustOptPass
Running pass: BPFASpaceCastSimplifyPass
```

These passes are registered in `BPFTargetMachine::registerPassBuilderCallbacks`
and added to the pipeline at the `EP_EarlyAsPossible` extension point (per
LLVM review D87153). They run for **all** BPF compilations regardless of
input language or frontend. The pass is a no-op when no
`llvm.preserve.*` intrinsics are present in the IR.

Verified end-to-end: hand-crafted LLVM IR with `llvm.preserve.struct.access.index`
intrinsics + `!llvm.preserve.access.index` metadata, when compiled through
the BPF pipeline, correctly produces:
- CO-RE global references like `@"llvm.task_struct:0:0$0:0"`
- `llvm.bpf.passthrough` intrinsics wrapping relocated accesses
- `.BTF.ext` section with `core_relo` records

## 2. Can we emit the LLVM intrinsics from Rust?

**Partially -- but with a fatal limitation.**

### What works: `#![feature(link_llvm_intrinsics)]`

Rust's unstable `link_llvm_intrinsics` feature allows declaring extern
functions with `#[link_name = "llvm.*"]` to call LLVM intrinsics directly:

```rust
#![feature(link_llvm_intrinsics)]

extern "C" {
    #[link_name = "llvm.preserve.struct.access.index.p0.p0"]
    fn preserve_struct_access(base: *const MyStruct, gep_idx: i32, di_idx: i32) -> *const u8;

    #[link_name = "llvm.bpf.passthrough.p0.p0"]
    fn bpf_passthrough(id: i32, ptr: *const u8) -> *const u8;

    #[link_name = "llvm.bpf.preserve.field.info.p0"]
    fn preserve_field_info(ptr: *const u8, kind: i64) -> i32;
}
```

This compiles and produces LLVM IR with the correct intrinsic calls:

```llvm
%field = call ptr @llvm.preserve.struct.access.index.p0.p0(ptr %task, i32 0, i32 0)
%field1 = call ptr @llvm.bpf.passthrough.p0.p0(i32 0, ptr %field)
```

### What does NOT work: the `elementtype` attribute

Since LLVM adopted opaque pointers, GEP-like intrinsics (including
`llvm.preserve.struct.access.index`) require the `elementtype` parameter
attribute on the pointer argument:

```llvm
; REQUIRED by LLVM verifier:
call ptr @llvm.preserve.struct.access.index.p0.p0(
    ptr elementtype(%struct.TaskStruct) %task, i32 0, i32 0)

; What Rust actually emits (REJECTED by LLVM verifier):
call ptr @llvm.preserve.struct.access.index.p0.p0(
    ptr %task, i32 0, i32 0)
```

The LLVM verifier rejects the call without `elementtype`:

```
Intrinsic requires elementtype attribute on first argument.
```

Rust's `link_llvm_intrinsics` mechanism has no way to attach parameter
attributes like `elementtype`. This is a **fundamental limitation** of the
current Rust -> LLVM codegen interface.

### What else is missing: `!llvm.preserve.access.index` metadata

Even if `elementtype` were solved, the `BPFAbstractMemberAccess` pass also
requires `!llvm.preserve.access.index` metadata on the intrinsic call,
pointing to a `DICompositeType` (debug info type) for the struct being
accessed:

```llvm
%field = call ptr @llvm.preserve.struct.access.index.p0.p0(
    ptr elementtype(%struct.task_struct) %task, i32 0, i32 0),
    !dbg !7, !llvm.preserve.access.index !8  ; <-- required metadata

!8 = !DICompositeType(tag: DW_TAG_structure_type, name: "task_struct", ...)
```

This metadata links the intrinsic call to the debug info type, which the pass
uses to generate CO-RE relocation records with the correct struct name and
field access path.

Rust has no mechanism to attach arbitrary metadata to function calls.

## 3. What does the `bpfel-unknown-none` target look like?

The target spec (from `rustc --print target-spec-json --target bpfel-unknown-none
-Z unstable-options`):

```json
{
  "arch": "bpf",
  "atomic-cas": false,
  "data-layout": "e-m:e-p:64:64-i64:64-i128:128-n32:64-S128",
  "dynamic-linking": true,
  "linker-flavor": "bpf",
  "llvm-target": "bpfel",
  "max-atomic-width": 64,
  "no-builtins": true,
  "obj-is-bitcode": true,
  "panic-strategy": "abort",
  "position-independent-executables": true,
  "singlethread": true,
  "target-pointer-width": 64,
  "metadata": { "tier": 3, "std": false, "host_tools": false }
}
```

Key observations:
- **`llvm-target: "bpfel"`** -- this is what triggers BPF-specific LLVM passes
- **`obj-is-bitcode: true`** -- rustc emits LLVM bitcode, not native object
  code. The linker (bpf-linker or lld) performs final compilation from
  bitcode to BPF object code. This is important because it means there's a
  bitcode stage where a custom tool could inject CO-RE intrinsics.
- No BPF-specific features or pass flags are set in the target spec.

## 4. Can `-C llvm-args` help?

**No useful BPF-specific flags exist for enabling CO-RE.**

Checked with `llc -march=bpfel --help-hidden` -- the only BPF-specific
options are:

- `--bpf-stack-size=<int>` -- stack size limit
- `--bpf-disable-avoid-speculation` -- speculation control
- `--bpf-disable-serialize-icmp` -- ICMP serialization
- `--bpf-disable-trap-unreachable` -- trap unreachable
- `--bpf-expand-memcpy-in-order` -- memcpy expansion
- `--disable-bpf-peephole` -- machine peephole opt
- `--disable-storeimm` -- store immediate insn

None of these relate to CO-RE or the `BPFAbstractMemberAccess` pass. The
pass is always enabled; the issue is producing the right input IR for it.

## 5. Current state of Rust BPF CO-RE

### aya-build compilation pipeline

The aya-build crate compiles Rust BPF programs with:
- `cargo build --target bpfel-unknown-none -Z build-std=core`
- `CARGO_ENCODED_RUSTFLAGS="-Cdebuginfo=2 -Clink-arg=--btf"`
- Emits bitcode (due to `obj-is-bitcode: true`), linked by bpf-linker or lld

The `--btf` flag tells the linker to emit BTF type information, which is
needed for struct_ops maps and type-aware BPF features. However, this is
**plain BTF**, not CO-RE relocations.

### Confirmed: no CO-RE relocations in current Rust BPF output

Inspected the compiled `scx_cosmos` BPF object file. The `.BTF.ext` section
header shows:

```
func_info: off=0 len=260
line_info: off=260 len=11996
core_relo: off=12256 len=0     <-- NO CO-RE relocations
```

The BTF.ext section contains function info and line info (debug metadata),
but zero CO-RE relocation records.

### How Rust struct access compiles

Rust compiles `#[repr(C)]` struct field access to byte-offset GEPs:

```rust
(*task).tgid  // field at offset 4
```

becomes:

```llvm
%0 = getelementptr inbounds i8, ptr %task, i64 4
%_0 = load i32, ptr %0, align 4
```

This uses a **byte offset** (`i64 4`), not a struct-aware GEP
(`getelementptr %struct.TaskStruct, ptr %task, i32 0, i32 1`). This is
because with opaque pointers, Rust's codegen doesn't need to specify the
struct type in the GEP.

For CO-RE, the access would need to be:

```llvm
%0 = call ptr @llvm.preserve.struct.access.index.p0.p0(
    ptr elementtype(%struct.TaskStruct) %task, i32 0, i32 1),
    !llvm.preserve.access.index !8
%_0 = load i32, ptr %0, align 4
```

### Existing related work

- **bpf-linker** (aya-rs/bpf-linker): A BPF static linker that links LLVM
  bitcode into BPF ELF objects. Does NOT have CO-RE awareness currently.

- **Michal Rostecki (Exein) RustLab talk**: "Enhancing Rust with BTF Debug
  Format Support" -- discussed BTF support for Rust BPF programs, focused on
  getting proper BTF type information rather than CO-RE relocations.

- **redbpf**: An older Rust BPF framework that compiled Rust to LLVM IR.
  Did not implement CO-RE support.

## 6. Possible approaches to enable Rust BPF CO-RE

### Approach A: Rustc compiler modification (best long-term solution)

Add CO-RE support directly to `rustc_codegen_llvm`:

1. Add a `#[preserve_access_index]` attribute (like Clang's
   `__attribute__((preserve_access_index))`)
2. When compiling struct field access for types with this attribute, emit
   `llvm.preserve.struct.access.index` intrinsics instead of byte-offset
   GEPs, with proper `elementtype` attributes and `!llvm.preserve.access.index`
   metadata
3. This is similar to how Clang handles `__builtin_preserve_access_index()`

**Pros**: Native, clean, works with the existing LLVM pipeline.
**Cons**: Requires RFC, compiler changes, stabilization -- multi-year effort.

### Approach B: Bitcode post-processing tool (pragmatic near-term)

Since `obj-is-bitcode: true` means rustc emits bitcode, a custom tool could:

1. Read the LLVM bitcode emitted by rustc
2. Identify struct field accesses (byte-offset GEPs) that should be CO-RE
   relocated, using debug info to map offsets back to struct members
3. Replace them with `llvm.preserve.struct.access.index` intrinsics with
   proper `elementtype` attributes and metadata
4. Write the modified bitcode for the linker to compile

This could be integrated into bpf-linker or run as a separate pass.

**Pros**: No compiler changes needed, works with existing Rust toolchain.
**Cons**: Fragile (depends on matching GEP patterns to struct accesses),
complex (requires LLVM bitcode manipulation), annotation mechanism needed
to mark which structs need CO-RE.

### Approach C: Custom LLVM pass via plugin (experimental)

LLVM supports loading pass plugins. A custom pass could:

1. Be loaded via `-C llvm-args=-load-pass-plugin=...`
2. Run early in the pipeline (before BPFAbstractMemberAccess)
3. Convert annotated struct accesses into preserve intrinsics

**Pros**: No compiler changes, no separate tool.
**Cons**: LLVM pass plugins have ABI stability issues, Rust's LLVM may not
support loading external plugins, annotation mechanism still needed.

### Approach D: Proc-macro + inline asm CO-RE helpers (workaround)

Use Rust procedural macros to generate CO-RE-aware field access code that
encodes relocation information in a custom ELF section:

```rust
#[core_field_access]
fn get_pid(task: *const task_struct) -> i32 {
    // Macro generates code that:
    // 1. Does the access with a known offset
    // 2. Emits a relocation record in a custom section
    // 3. The loader (aya) processes these custom relocations
}
```

This is essentially what aya could do as a userspace loader -- perform
relocations at load time based on BTF information, without LLVM CO-RE
support.

**Pros**: Works today, no compiler changes.
**Cons**: Non-standard, doesn't integrate with libbpf's CO-RE, requires
custom loader support in aya.

### Approach E: Emit LLVM IR directly from a proc macro (experimental)

Instead of going through Rust -> LLVM codegen, a proc macro could emit
LLVM IR text for CO-RE functions and use `global_asm!` or `asm!` to inject
it. However, BPF inline assembly has limited support in Rust and cannot
express the metadata needed for CO-RE.

## 7. Key technical barriers summary

| Barrier | Severity | Description |
|---------|----------|-------------|
| No `elementtype` attribute in `link_llvm_intrinsics` | **Critical** | LLVM verifier rejects preserve intrinsics without it |
| No metadata attachment from Rust | **Critical** | `!llvm.preserve.access.index` metadata cannot be emitted |
| Byte-offset GEPs | **High** | Rust emits `gep i8, ptr, i64 N` not struct-aware GEPs |
| No struct annotation | **Medium** | No way to mark structs for CO-RE (like C's `preserve_access_index`) |
| `link_llvm_intrinsics` is unstable | **Low** | Feature is internal and "strongly discouraged" |

## 8. Recommendation

For the aya-rs/scx struct_ops use case:

**Short-term**: CO-RE is not needed for struct_ops. The struct layout is
fixed by the running kernel's BTF, and aya already handles struct_ops map
creation using vmlinux BTF. Field offsets for struct_ops callback arguments
(like `struct task_struct *`) could be resolved at load time by aya using
BTF information, without requiring LLVM CO-RE relocations.

**Medium-term**: Approach B (bitcode post-processing) is the most pragmatic
path. The `obj-is-bitcode` property of the BPF target creates a natural
interception point. A tool (possibly integrated into bpf-linker) could
transform byte-offset GEPs into CO-RE preserve intrinsics using debug info.

**Long-term**: Approach A (rustc modification) is the right solution. An RFC
proposing `#[preserve_access_index]` for BPF targets, with corresponding
`rustc_codegen_llvm` changes to emit the right intrinsics with proper
attributes and metadata, would make Rust a first-class BPF CO-RE citizen.
