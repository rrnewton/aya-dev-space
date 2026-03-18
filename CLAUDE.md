# CLAUDE.md — aya-rs struct_ops development

## Orchestrator workflow

When the user gives a task, act as an **autonomous orchestrator**:

1. **Launch subagents in background** for parallelizable work. Give each
   a clear, self-contained prompt with enough context to finish the job.
2. **When a subagent completes**, immediately review its results.
   - If the goal is achieved: report success, commit, close issues.
   - If incomplete (ran out of context, hit a blocker, found a new issue):
     **autonomously launch a follow-up agent** to continue the work.
     Do NOT wait for the user to say "keep going."
3. **Keep relaunching** until the original goal is fully met — not just
   "it compiles" but "it compiles, runs, passes tests, and the feature
   works end-to-end."
4. Each relaunch should include the previous agent's findings in its
   prompt so it doesn't repeat work.
5. Only return to the user when the goal is truly done, or when a
   decision/clarification is needed that requires human judgment.

**Avoid these anti-patterns:**
- Reporting "agent finished, here's what it did" and waiting for "ok keep going"
- Treating a stalled agent (low turn count, no output) as complete
- Launching agents and immediately returning without checking results
- Summarizing partial results as if they're final

## Project layout

This is a parent repo that submodules the actual codebases:

- `~/work/aya-rs.dev/` — parent repo (this directory), tracked in git
  - `aya/` — aya-rs repo (submodule), branch `aya-scx`
  - `scx/` — sched-ext/scx repo (submodule), branch `aya-next`
  - `.beads/` — minibeads issue tracker (committed to parent repo)
  - `CLAUDE.md` — this file (committed to parent repo)

## Issue tracking

We use **minibeads** (`mb`) for issue tracking. Issues live in `.beads/`
and are committed to the parent repo.

```sh
mb quickstart        # get oriented with the CLI
mb ready             # see issues with no blockers (start here)
mb list              # see all issues
mb show aya-21       # show a specific issue
mb create "title" -d "description" -l label --parent aya-21
mb update aya-22 --status closed
```

Key parent issues:
- **aya-21**: aya struct_ops PR readiness cleanup (children: aya-22..aya-32)
- **aya-33**: eBPF-side struct_ops hackiness / compiler limitations (children: aya-34..aya-37)
- **aya-38**: Reusable SCX library crate
- **aya-39**: General vs struct_ops-specific kfunc support
- **aya-40**: PR splitting strategy

## Committing

- **aya/ and scx/** are submodules. Make clean, well-described commits
  on their respective branches (`aya-scx`, `aya-next`).
- **Parent repo** tracks `.beads/`, `CLAUDE.md`, and submodule refs.
  Commit here when updating issues or notes.
- After committing in a submodule, also update and commit the submodule
  ref in the parent repo.

## Building

### aya (the loader library)
```sh
cd aya && cargo build          # whole workspace
cargo clippy --lib -p aya -p aya-obj   # lint just the libs
```

### scx_purerust (the scheduler)
```sh
cd scx/scheds/rust/scx_purerust
cargo build --release          # builds eBPF + userspace
```

The eBPF build requires nightly Rust and builds `scx_purerust-ebpf`
as a sub-step via `aya-build` in `build.rs`. It compiles core from
source for the `bpfel-unknown-none` target.

### Running
```sh
sudo ./target/release/scx_purerust   # attach scheduler
# Ctrl-C to detach
```

## Key things learned about aya development

### aya-obj is `#![no_std]`
Uses `alloc::` for `String`, `Vec`, `BTreeMap`, etc. No `eprintln!`,
no `std::fs`. Use `log::debug!` for debug output (requires a logger
to be initialized in the consuming binary).

### BTF sanitization is critical
The kernel's `BPF_BTF_LOAD` rejects various BTF constructs:
- `BTF_FUNC_EXTERN` — rejected on some kernel builds even >= 5.17
- Unknown DATASEC section names (e.g. `.struct_ops.link`, `license`)
- DATASEC with zero size and no matching ELF section

aya's `fixup_and_sanitize()` runs in-place on `Btf`. If you need the
original types for later reference (e.g. kfunc FUNC entries), capture
the info BEFORE sanitization runs. The `to_bytes()` method is the
right place for "serialize-time-only" sanitization that shouldn't
affect the in-memory representation.

### BTF header must be recomputed after type replacement
When replacing a variable-size type (DataSec) with a fixed-size type
(Int) in `to_bytes()`, the serialized `type_len` changes. The
`to_bytes()` method must recompute `header.type_len`, `header.str_off`,
and `header.str_len` from the actual serialized data.

### struct_ops map creation needs the wrapper struct
The kernel has wrapper structs like `bpf_struct_ops_sched_ext_ops` that
wrap the actual struct (`sched_ext_ops`). The `btf_vmlinux_value_type_id`
field in `BPF_MAP_CREATE` must be the wrapper's BTF ID, not the inner
struct's. The `value_size` must be the wrapper's size. The struct data
goes at the `data` field's offset within the wrapper.

### struct_ops program loading
- `attach_btf_id` = vmlinux BTF type ID of the inner struct
- `expected_attach_type` = member index within the struct (not a real
  `bpf_attach_type` enum value)
- `prog_btf_fd` must be set (the loaded program BTF fd)

### Kfunc call resolution
The Rust BPF compiler emits kfunc calls as `BPF_PSEUDO_CALL` (src_reg=1)
with relocations to undefined extern symbols. aya must:
1. In `relocate_calls`: detect extern symbol relocs, patch src_reg to
   `BPF_PSEUDO_KFUNC_CALL` (2)
2. In `fixup_kfunc_calls`: look up the kfunc name in vmlinux BTF, set
   `insn.imm` to the vmlinux FUNC type ID

### Pre-existing test failures
`cargo clippy --all-targets` in the aya workspace has pre-existing
failures in `uprobe.rs` tests (`Path == str` comparison). These are not
related to struct_ops work.

### define_link_wrapper! macro
The `new()` method generated by this macro needs `pub(crate)` visibility
for struct_ops link creation from `bpf.rs`. This was done broadly in the
macro itself but should ideally be more targeted (see aya-28).
