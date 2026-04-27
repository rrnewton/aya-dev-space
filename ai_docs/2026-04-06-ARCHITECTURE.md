# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        BUILD TIME                                   │
│                                                                     │
│  Scheduler Source (.rs)                                              │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  scx_cosmos-ebpf/src/main.rs                             │       │
│  │                                                          │       │
│  │   core_read!(vmlinux::task_struct, p, scx.dsq_vtime)     │       │
│  │   bpf_global!(SLICE_NS: u64 = 10_000)                   │       │
│  │   bpf_map!(TASK_CTX: TaskStorage<TaskCtx> = ...)         │       │
│  │   kfuncs::dsq_insert(p, dsq, slice, flags)              │       │
│  └──────────────┬───────────────────────────────────────────┘       │
│                 │                                                    │
│                 ▼                                                    │
│  ┌──────────────────────────┐    ┌──────────────────────────┐       │
│  │  scx_ebpf library        │    │  scx_vmlinux             │       │
│  │                          │    │                          │       │
│  │  kfuncs.rs  (24 kfuncs)  │    │  build.rs reads          │       │
│  │  helpers.rs (core_read!) │    │  /sys/kernel/btf/vmlinux │       │
│  │  maps.rs    (BPF maps)   │    │  → bpftool → bindgen    │       │
│  │  global.rs  (BpfGlobal)  │    │  → vmlinux.rs structs   │       │
│  │  cpumask.rs (14 kfuncs)  │    │                          │       │
│  │  timer.rs   (bpf_timer)  │    │  Provides: task_struct,  │       │
│  │  kptr.rs    (Kptr<T>)    │    │  sched_ext_entity, etc.  │       │
│  └──────────────┬───────────┘    └────────────┬─────────────┘       │
│                 │                              │                     │
│                 ▼                              ▼                     │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  rustc + LLVM  (target: bpfel-unknown-none)              │       │
│  │                                                          │       │
│  │  • Compiles Rust → LLVM IR → BPF bytecode               │       │
│  │  • core::arch::asm!("call {func}") → BPF CALL insns     │       │
│  │  • offset_of!(task_struct, scx.dsq_vtime) → constant    │       │
│  │  • #[link_section = ".maps"] → BPF map definitions       │       │
│  │  • #[link_section = ".aya.core_relo"] → CO-RE markers    │       │
│  │                                                          │       │
│  │  Output: ELF object (bpfel)                              │       │
│  └──────────────┬───────────────────────────────────────────┘       │
│                 │                                                    │
│                 ▼                                                    │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  aya-core-postprocessor  (called by aya-build)           │       │
│  │                                                          │       │
│  │  1. Parse .aya.core_relo markers from ELF                │       │
│  │  2. Read vmlinux BTF for field offset resolution         │       │
│  │  3. Scan BPF instructions for matching offsets           │       │
│  │     (ALU64 ADD IMM, STX MEM, LDX MEM patterns)          │       │
│  │  4. Create stub struct definitions in program BTF        │       │
│  │  5. Generate bpf_core_relo records in .BTF.ext           │       │
│  │  6. Patch the ELF with updated .BTF and .BTF.ext         │       │
│  │                                                          │       │
│  │  Output: ELF with CO-RE relocation records               │       │
│  └──────────────┬───────────────────────────────────────────┘       │
│                 │                                                    │
│                 ▼                                                    │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  Userspace Loader  (scx_cosmos/src/main.rs)              │       │
│  │                                                          │       │
│  │  Uses aya library to:                                    │       │
│  │  • Parse the BPF ELF                                     │       │
│  │  • Override globals (SLICE_NS, CPU_UTIL, etc.)           │       │
│  │  • Set up perf events, topology detection                │       │
│  └──────────────┬───────────────────────────────────────────┘       │
│                 │                                                    │
└─────────────────┼───────────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        LOAD TIME                                    │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  aya-obj  (in userspace loader process)                  │       │
│  │                                                          │       │
│  │  1. Parse ELF sections, BTF, maps, programs              │       │
│  │  2. fixup_and_sanitize_btf():                            │       │
│  │     • Remove EXTERN FUNCs (kernel rejects them)          │       │
│  │     • Replace unknown DATASECs with INT placeholders     │       │
│  │     • Transform Kptr<T> → PTR→TYPE_TAG("kptr")→T        │       │
│  │     • Attach BTF to .bss/.data maps for kptr support     │       │
│  │  3. BPF_BTF_LOAD → kernel validates and stores BTF       │       │
│  │  4. relocate_calls():                                    │       │
│  │     • Detect extern symbol (kfunc) relocations           │       │
│  │     • Patch src_reg from BPF_PSEUDO_CALL (1) to          │       │
│  │       BPF_PSEUDO_KFUNC_CALL (2)                          │       │
│  │  5. fixup_kfunc_calls():                                 │       │
│  │     • Look up kfunc names in vmlinux BTF                 │       │
│  │     • Set insn.imm = vmlinux FUNC type ID                │       │
│  │  6. relocate_btf() (CO-RE):                              │       │
│  │     • Read .BTF.ext bpf_core_relo records                │       │
│  │     • Match local struct types to target (vmlinux) types │       │
│  │     • Patch instruction offsets:                         │       │
│  │       ALU64: insn.imm = new_offset                       │       │
│  │       LDX/STX: insn.off = new_offset                    │       │
│  │  7. BPF_PROG_LOAD for each program                       │       │
│  │  8. BPF_MAP_CREATE for struct_ops map                     │       │
│  │     • btf_vmlinux_value_type_id = wrapper struct ID      │       │
│  │     • Program FDs placed at correct member offsets        │       │
│  │  9. BPF_LINK_CREATE to attach struct_ops                  │       │
│  └──────────────┬───────────────────────────────────────────┘       │
│                 │                                                    │
└─────────────────┼───────────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        KERNEL RUNTIME                               │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  BPF Verifier                                            │       │
│  │                                                          │       │
│  │  • Validates each program instruction-by-instruction     │       │
│  │  • Tracks register types (PTR_TO_MAP_VALUE, trusted_ptr) │       │
│  │  • Verifies kfunc call signatures against vmlinux BTF    │       │
│  │  • Checks field write permissions (btf_struct_access)    │       │
│  │  • Ensures bounded loops, stack limits, ref counting     │       │
│  └──────────────┬───────────────────────────────────────────┘       │
│                 │                                                    │
│                 ▼                                                    │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  JIT Compiler                                            │       │
│  │                                                          │       │
│  │  BPF bytecode → native x86_64 machine code               │       │
│  │  • BPF registers → x86 registers                         │       │
│  │  • BPF CALL → native function call                       │       │
│  │  • Runs at native speed                                  │       │
│  └──────────────┬───────────────────────────────────────────┘       │
│                 │                                                    │
│                 ▼                                                    │
│  ┌──────────────────────────────────────────────────────────┐       │
│  │  sched_ext Framework                                     │       │
│  │                                                          │       │
│  │  Kernel calls our BPF programs on scheduling events:     │       │
│  │                                                          │       │
│  │  Task wakeup ──→ select_cpu() ──→ enqueue()              │       │
│  │  CPU idle    ──→ dispatch()                               │       │
│  │  Task starts ──→ running()                                │       │
│  │  Task stops  ──→ stopping()                               │       │
│  │  Scheduler   ──→ init() / exit()                          │       │
│  └──────────────────────────────────────────────────────────┘       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Detailed Example: `core_read!` from source to execution

This traces how a single field read flows through the entire system.

### Step 1: Source code (Rust)

```rust
// In scx_cosmos-ebpf/src/main.rs, inside on_running():
let vtime = core_read!(vmlinux::task_struct, p, scx.dsq_vtime)?;
```

### Step 2: Macro expansion

`core_read!` expands to three parts:

```rust
// Part A: CO-RE marker (compile-time constant)
const _: () = {
    const __MARKER: CoreReloMarkerData = build_core_relo_marker(
        b"vmlinux :: task_struct",  // stringify!($struct_ty)
        b"scx . dsq_vtime",        // stringify!($($field).+)
    );
    #[link_section = ".aya.core_relo"]
    #[used]
    static __CORE_RELO: [u8; N] = /* marker bytes: 0xAC + name + path */;
};

// Part B: Offset computation (compile-time)
let offset = core::mem::offset_of!(vmlinux::task_struct, scx.dsq_vtime);
// → evaluates to e.g. 912 on kernel 6.13

// Part C: Probe read (runtime)
let typed_ptr = &raw const (*(p as *const task_struct)).scx.dsq_vtime;
probe_read_kernel::<u64>(typed_ptr)
// → calls bpf_probe_read_kernel(dst, 8, src)
```

### Step 3: Compilation (rustc + LLVM → BPF bytecode)

LLVM compiles the probe_read_kernel call to BPF instructions:

```
; Part B: compute source pointer (p + 912)
r6 = r8            ; r6 = task_struct ptr (save in callee-saved reg)
r6 += 912          ; r6 = &p->scx.dsq_vtime (ALU64 ADD IMM)

; Part C: call bpf_probe_read_kernel(stack_slot, 8, r6)
r1 = r10           ; r1 = frame pointer
r1 += -8           ; r1 = &stack_slot (destination)
r2 = 8             ; r2 = size
r3 = r6            ; r3 = source pointer
call 113           ; bpf_probe_read_kernel helper

; Read result from stack
r1 = *(u64 *)(r10 - 8)   ; load the value
```

The `.aya.core_relo` section contains the marker bytes:
```
[0xAC, 11, "task_struct", 14, "scx.dsq_vtime"]
```

### Step 4: Post-processing (aya-core-postprocessor)

Called by `aya-build` after compilation. The postprocessor:

1. **Reads markers** from `.aya.core_relo` section:
   - struct_name = "task_struct"
   - field_path = "scx.dsq_vtime"

2. **Resolves field offset from vmlinux BTF**:
   - Finds `task_struct` in vmlinux BTF (type ID 115)
   - Walks `scx` member → `sched_ext_entity` → `dsq_vtime` member
   - Computes byte offset = 912 (on kernel 6.13)

3. **Scans BPF instructions** for `ALU64 ADD IMM` with `imm = 912`:
   - Finds the instruction `r6 += 912` in the `struct_ops/running` section
   - Records: section="struct_ops/running", insn_index=2

4. **Creates stub struct** in program BTF:
   ```
   struct task_struct {
       struct sched_ext_entity scx;  // offset 0 (placeholder)
   }
   struct sched_ext_entity {
       u64 dsq_vtime;               // offset determined by vmlinux
   }
   ```

5. **Generates CO-RE relocation record** in `.BTF.ext`:
   ```
   bpf_core_relo {
       insn_off: <byte offset of r6 += 912 instruction>,
       type_id: <BTF ID of local task_struct stub>,
       access_str_off: "0:0:0",  // task_struct[0].scx[0].dsq_vtime[0]
       kind: BPF_CORE_FIELD_BYTE_OFFSET,
   }
   ```

### Step 5: Loading (aya loader)

When the scheduler starts, aya processes the ELF:

1. **`relocate_btf()`** reads the CO-RE record from `.BTF.ext`

2. **Matches local type** (stub `task_struct.scx.dsq_vtime`) against
   **target type** (vmlinux `task_struct.scx.dsq_vtime`)

3. **Computes target offset**: On the running kernel's vmlinux BTF,
   `dsq_vtime` might be at offset 916 (if `selected_cpu` was added)

4. **Patches the instruction**:
   - Before: `r6 += 912`  (compiled offset)
   - After:  `r6 += 916`  (target kernel offset)

   The patching code in `relocation.rs`:
   ```rust
   match class {
       BPF_ALU | BPF_ALU64 => { ins.imm = target_value as i32; }
       BPF_LDX | BPF_ST | BPF_STX => { ins.off = target_value as i16; }
   }
   ```

### Step 6: Verification and JIT

The kernel verifier sees:
```
r6 = r8                    ; R6 = trusted_ptr_task_struct
r6 += 916                  ; R6 = trusted_ptr_task_struct(off=916)
                           ; verifier checks: 916 = valid dsq_vtime offset ✓
call bpf_probe_read_kernel ; reads 8 bytes from r6
```

Then the JIT compiler converts BPF to native x86_64 and the
instruction runs at full native speed.


## Repository Structure

```
aya-rs.dev/                       ← parent repo (this directory)
├── CLAUDE.md                     ← development workflow, PORT_TODO rules
├── README.md                     ← project overview
├── ARCHITECTURE.md               ← this document
├── .beads/                       ← minibeads issue tracker
│   └── issues/                   ← aya-1 through aya-73
├── docs/
│   ├── cosmos-port-mapping.md    ← C→Rust function mapping
│   ├── safe-bpf-map-types.md    ← research on safe BPF APIs
│   └── llvm_bpf_core_research.md ← LLVM CO-RE pass analysis
├── results/
│   ├── sweep-6.13/              ← EEVDF vs C vs Rust cosmos benchmarks
│   └── sweep-6.16/              ← EEVDF vs C cosmos on 6.16
├── testing/
│   ├── run-in-vm.sh             ← virtme-ng VM test runner
│   ├── sweep-6.13.sh            ← full benchmark sweep script
│   └── benchmark.sh             ← individual benchmark harness
│
├── aya/                          ← aya-rs fork (branch: aya-scx.v2)
│   ├── aya-obj/src/
│   │   ├── obj.rs               ← ELF parsing, struct_ops sections
│   │   ├── btf/btf.rs           ← BTF sanitization, kptr injection
│   │   └── btf/relocation.rs    ← CO-RE relocation patching
│   ├── aya/src/
│   │   ├── bpf.rs               ← struct_ops attach, cached kernel BTF
│   │   └── programs/struct_ops.rs ← StructOps program type
│   ├── aya-build/src/lib.rs     ← postprocessor integration
│   ├── aya-core-postprocessor/  ← CO-RE postprocessor (new crate)
│   │   ├── btf_parser.rs        ← BTF reading + stub struct creation
│   │   ├── insn_scanner.rs      ← ALU/STX/LDX instruction matching
│   │   ├── btf_ext_writer.rs    ← .BTF.ext generation
│   │   ├── elf_patcher.rs       ← ELF section replacement
│   │   └── marker_parser.rs     ← .aya.core_relo section parsing
│   └── aya-core-relo-macro/     ← proc macro for CO-RE markers
│
└── scx/                          ← sched-ext/scx fork (branch: aya-next)
    ├── rust/
    │   ├── scx_ebpf/src/        ← shared eBPF library
    │   │   ├── kfuncs.rs        ← 24 sched_ext kfunc wrappers
    │   │   ├── helpers.rs       ← core_read!, core_write!, bpf_for!
    │   │   ├── maps.rs          ← BPF map types (HashMap, PerCpuArray, etc.)
    │   │   ├── global.rs        ← BpfGlobal<T>, BpfGlobalArray<T,N>
    │   │   ├── cpumask.rs       ← 14 bpf_cpumask kfunc wrappers
    │   │   ├── timer.rs         ← BPF timer helpers
    │   │   ├── kptr.rs          ← Kptr<T>, kptr_xchg, RCU lock/unlock
    │   │   └── ops.rs           ← sched_ext_ops struct definition
    │   ├── scx_ebpf_derive/     ← proc macro: scx_ops_define!
    │   └── scx_vmlinux/         ← build-time vmlinux→Rust struct gen
    └── scheds/rust_only/
        ├── scx_cosmos/          ← production cosmos scheduler
        │   ├── src/main.rs      ← userspace loader (clap CLI, topology)
        │   └── scx_cosmos-ebpf/
        │       └── src/main.rs  ← BPF scheduler (~2000 lines)
        └── scx_simple/          ← minimal FIFO scheduler
            └── scx_simple-ebpf/
                └── src/main.rs  ← BPF scheduler (~100 lines)
```

## Component Interactions

### Kfunc Call Resolution

```
Rust source:              kfuncs::kick_cpu(cpu, flags)
    │
    ▼ (macro/inline)
Inline asm:               asm!("call {f}", f = sym scx_bpf_kick_cpu, ...)
    │
    ▼ (rustc/LLVM)
BPF bytecode:             call #0  (src_reg=1, BPF_PSEUDO_CALL)
                          + R_BPF_64_32 reloc → "scx_bpf_kick_cpu"
    │
    ▼ (aya relocate_calls)
Patched:                  call #0  (src_reg=2, BPF_PSEUDO_KFUNC_CALL)
    │
    ▼ (aya fixup_kfunc_calls)
Resolved:                 call #133369  (imm = vmlinux BTF func ID)
    │
    ▼ (kernel verifier + JIT)
Native x86:               call <kernel function address>
```

### BTF Sanitization Pipeline

```
Program BTF (from ELF)
    │
    ▼ fixup_kptr_types()
    │  Kptr<bpf_cpumask> → PTR → TYPE_TAG("kptr") → STRUCT bpf_cpumask
    │
    ▼ fixup_func_linkage()
    │  GLOBAL funcs → STATIC (struct_ops requirement)
    │
    ▼ to_bytes() sanitization
    │  • EXTERN FUNCs → removed
    │  • Unknown DATASECs (.struct_ops.link, .aya.*) → INT placeholders
    │  • Recompute header.type_len, header.str_off
    │
    ▼ BPF_BTF_LOAD
    Kernel accepts sanitized BTF
```

### struct_ops Map Creation

```
Kernel vmlinux BTF:
    bpf_struct_ops_sched_ext_ops  (wrapper struct)
        └── data: sched_ext_ops  (inner struct)
                ├── select_cpu  (member index 0)
                ├── enqueue     (member index 1)
                ├── dispatch    (member index 2)
                └── ...

aya creates BPF_MAP_TYPE_STRUCT_OPS:
    btf_vmlinux_value_type_id = wrapper's BTF ID
    value_size = wrapper's size
    key_size = 4

    Map value layout:
    ┌──────────────────────────────┐
    │  wrapper padding/fields      │
    ├──────────────────────────────┤
    │  data.select_cpu = prog_fd   │  ← program FD at member offset
    │  data.enqueue    = prog_fd   │
    │  data.dispatch   = prog_fd   │
    │  data.timeout_ms = 5000      │  ← data field at member offset
    │  data.name       = "cosmos"  │
    │  data.flags      = 54        │
    └──────────────────────────────┘

BPF_LINK_CREATE attaches the map → kernel installs the scheduler
```
