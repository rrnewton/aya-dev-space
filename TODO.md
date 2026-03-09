# aya-rs struct_ops TODO

Tracking remaining work to get aya struct_ops support PR-ready and to
make the scx_purerust scheduler as idiomatic as possible.

Status: **working at runtime** as of 2025-03-09. The scheduler attaches,
runs for 5+ minutes, and detaches cleanly. What follows is cleanup and
polish.

---

## A. aya code quality issues (must fix before PR)

### A1. Dead code: `register_kfunc` API is unused at runtime
The `KfuncSignature`, `KfuncParamType`, `register_kfunc()`, and
`apply_kfunc_registrations()` add FUNC_PROTO + FUNC EXTERN entries
to program BTF, but these are immediately sanitized to INT placeholders
in `to_bytes()` because the kernel rejects `BTF_FUNC_EXTERN` during
`BPF_BTF_LOAD`. Kfunc resolution actually happens via vmlinux BTF
lookup in `fixup_kfunc_calls()`. Either:
- Remove the entire register_kfunc machinery (simplest), or
- Make it actually work by using a split BTF approach (load sanitized
  BTF, keep original for prog_load), or
- Gate the EXTERN sanitization on a kernel feature probe

### A2. Dead field: `Object.kfunc_btf_ids`
Populated in `fixup_and_sanitize_btf` but never read. `fixup_kfunc_calls`
resolves against vmlinux directly. Remove the field.

### A3. Duplicate doc comment on `Btf::to_bytes()`
Line has both `/// Encodes the metadata as BTF format` and
`/// Encodes the metadata as BTF format.` (duplicate).

### A4. `unsafe { transmute }` for `expected_attach_type`
In `attach_struct_ops`, member index is cast to `bpf_attach_type` via
`core::mem::transmute`. The `ProgramData` should accept a raw `u32`
for `expected_attach_type` to avoid this.

### A5. Unused `struct_size` variable
After adding `wrapper_size`, `struct_size` is still bound but only used
indirectly. Clean up.

### A6. `bpf_map_create` visibility change (`pub(super)` → `pub(crate)`)
Unrelated collateral. Either revert and use a dedicated struct_ops map
creation function, or justify the visibility change separately.

### A7. `links.rs` macro change is too broad
Making `new()` `pub(crate)` + `#[allow(private_interfaces)]` on the
`define_link_wrapper!` macro affects ALL link wrapper types, not just
`StructOpsLink`. Find a targeted solution.

### A8. No tests
No unit tests for: section parsing, BTF fixups, kfunc call patching,
struct_ops map creation/attachment, BTF sanitization in `to_bytes()`.

### A9. `license` DATASEC sanitization is overly broad
Replacing ALL `license` DATASECs with INT in `to_bytes()` could break
non-struct_ops programs. Should be more targeted — only sanitize when
the kernel actually rejects it, or only for struct_ops objects.

### A10. `Btf::from_sys_fs()` called twice
Once in `EbpfLoader::new()` and again inside `attach_struct_ops()`.
Should reuse the existing kernel BTF.

### A11. `attach_struct_ops` does too much
~200-line method that loads programs, creates maps, builds value
buffers, and attaches. Should be split into smaller methods.

---

## B. scx_purerust eBPF-side hackiness (compiler/toolchain limitations)

These are NOT aya bugs — they're Rust BPF compiler limitations that
require workarounds in eBPF code. Addressing them requires either
upstream compiler work or aya-ebpf procedural macros.

### B1. `scx_ops_define!` macro (278 lines)
Manually defines every callback trampoline. Should be replaced by a
proc macro that reads the kernel struct definition from vmlinux BTF
and auto-generates trampolines. This belongs in aya-ebpf or a
dedicated `aya-sched-ext` crate.

### B2. Inline asm kfunc wrappers (78 lines)
The Rust BPF compiler emits broken `call -1; exit` for `extern "C"`
kfunc declarations. Workaround: inline assembly. Fix requires:
- Rust BPF backend generating `BPF_PSEUDO_KFUNC_CALL` for extern fns
- Or an aya-ebpf `#[kfunc]` attribute macro

### B3. Opaque vmlinux type stubs (19 lines)
Manual `task_struct { _opaque: i32 }` stubs. Should be auto-generated
from vmlinux BTF using aya-gen or equivalent.

### B4. Manual `sched_ext_ops` struct definition (72 lines)
Manually mirrors the kernel struct with 40 fields. Must be kept in sync
with kernel changes. Should be auto-generated from vmlinux BTF.

---

## C. scx_purerust elegance plan

Goal: defining a sched_ext scheduler in Rust should look like this:

```rust
// eBPF side (scx_purerust-ebpf/src/main.rs) — the IDEAL
#![no_std]
#![no_main]
use aya_ebpf_scx::prelude::*;

#[scx_scheduler("purerust")]
mod sched {
    fn enqueue(p: &mut TaskStruct, enq_flags: u64) {
        scx::dsq_insert(p, SHARED_DSQ, SLICE_DFL, enq_flags);
    }
    fn dispatch(_cpu: i32, _prev: &mut TaskStruct) {
        scx::dsq_move_to_local(SHARED_DSQ);
    }
    fn init() -> i32 {
        scx::create_dsq(SHARED_DSQ, -1)
    }
}
```

```rust
// Userspace side (src/main.rs) — the IDEAL
use aya::Ebpf;
let mut ebpf = Ebpf::load(include_bytes_aligned!(...))?;
let link = ebpf.attach_struct_ops("_scx_ops")?;
```

### Current state vs ideal

| Component | Current (548 lines) | Ideal | Gap |
|-----------|------------|-------|-----|
| Scheduler logic | 15 lines in main.rs | Same | None |
| Trampolines | 278 lines, `scx_ops_define!` macro | 0 lines, proc macro generates | Needs proc macro |
| Kfunc wrappers | 78 lines, inline asm | 0 lines, `extern "C"` just works | Needs compiler fix |
| vmlinux stubs | 19 lines, manual | 0 lines, auto-generated | Needs aya-gen |
| sched_ext_ops | 72 lines, manual struct | 0 lines, auto-generated | Needs aya-gen |
| Userspace loader | 63 lines | ~10 lines | Remove dead `register_kfunc` |

### C1. Immediate cleanup (no new crates needed)

**Userspace (src/main.rs):**
- Remove `register_kfunc` calls — they're dead code (see A1)
- This simplifies from 63 lines to ~25 lines

**eBPF (scx_purerust-ebpf/src/main.rs):**
- Already clean — 80 lines of real scheduler logic
- The `compat/` module is well-organized with clear HACK markers

### C2. Reusable SCX library crate (medium-term)

Create `scx-ebpf` (or `aya-scx-ebpf`) crate in the scx repo containing:

```
scx-ebpf/
├── src/
│   ├── lib.rs           # pub mod prelude, re-exports
│   ├── ops.rs           # sched_ext_ops struct (auto-gen from vmlinux BTF)
│   ├── kfuncs.rs        # scx_bpf_* inline asm wrappers
│   └── vmlinux.rs       # task_struct, scx_exit_info stubs
└── Cargo.toml
```

This lets any scheduler do:
```rust
use scx_ebpf::prelude::*;
```

Instead of each scheduler maintaining its own `compat/` directory.

The `scx_ops_define!` macro moves here too, and a scheduler's
eBPF main.rs becomes just scheduler logic + registration.

### C3. Proc macro for struct_ops (longer-term, aya upstream)

A `#[struct_ops]` proc macro in aya-ebpf that:
1. Reads the kernel struct definition from vmlinux BTF at build time
2. Generates the trampoline functions (ctx pointer extraction)
3. Generates the `.struct_ops.link` static
4. Generates the `Option<fn>` struct type

This eliminates `struct_ops.rs` entirely. Each callback becomes a
normal Rust function annotated with `#[scx_callback]` or similar.

### C4. Compiler-level kfunc support (longest-term)

Requires the Rust BPF backend to:
- Emit `BPF_PSEUDO_KFUNC_CALL` for `extern "C"` function calls
- Generate proper BTF FUNC_PROTO entries for extern declarations

This eliminates the inline assembly wrappers entirely. Each kfunc
becomes a simple `extern "C" { fn scx_bpf_dsq_insert(...); }` call.

### Phased approach

**Phase 1 (now):** Clean up aya PR issues (section A) + remove dead
`register_kfunc` from scx_purerust userspace.

**Phase 2:** Extract `scx-ebpf` reusable crate from `compat/`. Multiple
schedulers can share it.

**Phase 3:** Build `scx_ops_define!` as a proc macro (in scx-ebpf or
aya-ebpf) that auto-generates trampolines from vmlinux BTF.

**Phase 4:** Upstream Rust BPF compiler kfunc support. Removes all
inline assembly.

---

## D. Architectural questions for upstream discussion

### D1. Should kfunc support be general or struct_ops-specific?
Other BPF program types (tracing, XDP, TC) can also call kfuncs.
The current implementation only handles kfuncs in the context of
struct_ops. A general solution would benefit more users.

### D2. Reusable SCX library crate?
Should scx_purerust's `compat/` module become a standalone crate
(e.g., `scx-rs` or `aya-sched-ext`) that provides:
- Auto-generated `sched_ext_ops` struct from vmlinux BTF
- `scx_ops_define!` proc macro
- Type-safe kfunc wrappers for scx_bpf_* functions

### D3. Split the PR?
The aya changes could be split into multiple PRs:
1. aya-obj: section parsing + BTF types made public
2. aya-obj: BTF sanitization fixes (EXTERN, DATASEC, header recompute)
3. aya-obj: kfunc call relocation support
4. aya: StructOps program type + map handling + attachment
5. aya: kfunc registration API (if kept)

---

## E. Testing checklist

- [ ] `cargo fmt && cargo clippy --all-targets` passes in aya workspace
- [ ] `cargo fmt && cargo clippy --all-targets` passes in scx_purerust
- [ ] `cargo build --release` for scx_purerust
- [ ] `sudo ./target/release/scx_purerust` — scheduler attaches
- [ ] Ctrl-C — scheduler detaches cleanly
- [ ] System remains responsive during scheduling
- [ ] Run for 5+ minutes under load
- [ ] Unit tests pass (once written)
