# CLAUDE.md — aya-rs struct_ops development

## A note for ORC specifically

If you are an agent with the orc orchestrator, read this section, otherwise skip it.

Note that this is a Github/OSS workflow. We use git, and the `gh`
(github CLI), NOT internal Meta tasks and mercurial/sapling.

Moreover this project uses a version controlled task graph using
minibeaads (`mb`) as described below.  You will fork your parallel
suborc agents in the separate git worktrees and they will use your
internal `tg` tool for managing task graphs.  There is no tg<>mb sync
directly.  Instead, you will use `tg` for agent orchestration, but
when you COMMIT to git, you will summarize a high level status of
what's worked on and what's left inside durable beads issues that are
committed to the repository.

Make sure that the next person/agent that picks up the repository will
be able to understand the status just from the beads issues, without
reference to tg graphs that only exist on THIS machine.

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
  - `rsched/` — rsched repo (submodule)
  - `.beads/` — minibeads issue tracker (committed to parent repo)
  - `ai_docs/` — transient AI-generated docs (dated, version-controlled)
  - `experiments/` — benchmark data and results (raw data version-controlled)
  - `testing/` — benchmark and test scripts
  - `CLAUDE.md` — this file (committed to parent repo)

Additional git worktrees for parallel agent work live under
`~/work/multi_sched-test/worktrees/` (e.g. aya2, aya3, aya4).

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
- **aya-33**: eBPF-side struct_ops hackiness / compiler limitations (P3 improvement)
- **aya-38**: Reusable SCX library crate
- **aya-56**: Cosmos on kernel 6.16+ (CO-RE + kfunc setters)
- **aya-57**: Cosmos port accuracy audit
- **aya-58**: Fix cosmos port bugs found in audit (children: aya-59..aya-73)

## PORT_TODO discipline

The cosmos port aims for **100% feature parity** with the C original.
No silent compromises, workarounds, or simplified alternatives.

### Rules:
1. **Every gap gets a PORT_TODO comment** in the source code with a
   brief explanation of what's missing and why.
2. **Every PORT_TODO gets a beads issue** (`mb create`) under the
   appropriate parent issue, with label `port-gap`.
3. **Never say "we skip X"** without filing an issue. If we can't do
   something due to a toolchain limitation, that's a tracked blocker,
   not an acceptable simplification.
4. **Comments must say what IS missing**, not imply it's fine. Example:
   - BAD: `// We skip the is_smt_contended check since we don't have
     LLC IDs in pure Rust BPF.`
   - GOOD: `// PORT_TODO(aya-XX): is_smt_contended check missing.
     Requires per-CPU LLC IDs which need CO-RE field access to
     cpu_llc_id. Tracked as a port gap.`
5. **Close PORT_TODOs** by implementing the feature, not by rationalizing
   why it's unnecessary.

### Mapping document:
See `docs/cosmos-port-mapping.md` for the complete C→Rust function
mapping, including all gaps and their tracking issues.

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

### scx_cosmos (the production scheduler)
```sh
cd scx/scheds/rust_only/scx_cosmos
cargo build --release          # builds eBPF + userspace
# For kernel 6.16+:
SCX_VMLINUX_BTF=/lib/modules/6.16.0/build/vmlinux \
  cargo build --release --features kernel_6_16
```

### scx_simple (the FIFO scheduler)
```sh
cd scx/scheds/rust_only/scx_simple
cargo build --release
```

The eBPF build requires nightly Rust and builds `scx_purerust-ebpf`
as a sub-step via `aya-build` in `build.rs`. It compiles core from
source for the `bpfel-unknown-none` target.

### Running
```sh
sudo ./target/release/scx_cosmos   # attach cosmos scheduler
sudo ./target/release/scx_simple   # attach simple FIFO scheduler
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

## Repo hygiene conventions

- **Keep git status clean.** Don't leave uncommitted changes in the parent
  repo. Use branches for experimental work.
- **Transient docs** (AI-generated reports, session notes, roadmaps) go in
  `ai_docs/` with date prefixes (e.g. `2026-04-27-arena-design.md`).
- **Experiment data** goes in `experiments/`. Version-control raw data (CSV,
  txt) but not logs or binary artifacts. Each experiment directory must have
  metadata documenting kernel version, hardware, and date.
- **Large/binary outputs** go in gitignored directories. Each should have a
  README explaining what goes there.
- **Worktrees** for parallel agent work live under
  `~/work/multi_sched-test/worktrees/`. Only the primary `aya/` submodule
  checkout is in the parent repo. Worktree dirs in the parent repo are
  gitignored.
