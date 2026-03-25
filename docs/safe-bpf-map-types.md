# Safe BPF Map Access via Rust's Type System

**Date**: 2026-03-25
**Status**: Research / design exploration

## 1. Problem Statement

### What the BPF verifier guarantees

When a BPF program calls `bpf_map_lookup_elem()`, the kernel returns a
pointer into kernel memory. The BPF verifier tracks this pointer as
`PTR_TO_MAP_VALUE` (or `PTR_TO_MAP_VALUE_OR_NULL` before a null check) and
enforces the following invariants:

1. **Null check required**: The pointer is `PTR_TO_MAP_VALUE_OR_NULL` until
   the program branches on its nullity. Only after a successful null check
   can the pointer be dereferenced.

2. **Bounded access**: Reads/writes through the pointer are bounds-checked
   against the map's `value_size`.

3. **Invalidation on helper calls**: Any call to a BPF helper or kfunc may
   invalidate map value pointers. The verifier tracks this internally and
   rejects programs that dereference a pointer after a helper call that could
   have invalidated it. Specifically, `release_on_unlock` and
   `invalidate_non_owning_refs` mechanisms ensure that pointers obtained from
   map lookups are not used across operations that could modify the underlying
   data.

### What Rust currently provides

In aya-ebpf (the BPF-side Rust crate), the current map API looks like this:

```rust
// HashMap::get — marked unsafe
pub unsafe fn get(&self, key: impl Borrow<K>) -> Option<&V>

// HashMap::get_ptr — returns raw pointer, caller decides
pub fn get_ptr(&self, key: impl Borrow<K>) -> Option<*const V>

// HashMap::get_ptr_mut — returns raw mutable pointer
pub fn get_ptr_mut(&self, key: impl Borrow<K>) -> Option<*mut V>
```

The `get()` method is `unsafe` because:
- Without `BPF_F_NO_PREALLOC`, removed entries can be aliased by new entries,
  causing reads of garbage or corruption on writes
- The returned `&V` reference has a fabricated `'a` lifetime (not tied to any
  real borrow) and can be held across helper calls that invalidate the pointer

The raw pointer variants (`get_ptr`, `get_ptr_mut`) push all safety
responsibility to the caller.

### The gap

We want a safe API where:
- Map value references cannot be used after a BPF helper/kfunc call
- The reference lifetime is scoped to a "no-helper-calls" region
- It compiles to zero-overhead BPF bytecode (no runtime cost)
- It works in `#![no_std]` with no allocator
- It is ergonomic enough that scheduler authors will use it

The fundamental challenge: Rust's lifetime system expresses "valid as long as
the borrow exists" but not "valid until a specific event occurs." We need to
encode the concept of *invalidation by an external action* in the type system.

## 2. Survey of Existing Approaches

### 2.1 What other BPF frameworks do

**aya-ebpf** (current): Returns `unsafe fn get() -> Option<&V>` with a
fabricated lifetime, or raw pointers. No attempt at encoding invalidation.
The `RingBuf` API is more sophisticated — it returns `RingBufEntry<T>` with
`#[must_use]` that must be `.submit()` or `.discard()` — but this is RAII
for a different problem (resource cleanup, not pointer validity).

**redbpf**: Returns `Option<&V>` and `Option<&mut V>` from `get()` and
`get_mut()`, requiring `&mut self` for the map. This provides some safety
against concurrent access (you can't hold two `&mut` borrows) but does
*not* address invalidation by helper calls. The `&mut self` requirement is
also overly conservative — you should be able to read from a map while
holding a reference to a different map.

**libbpf-rs**: BPF-side programs are written in C, not Rust. libbpf-rs only
provides userspace APIs. No BPF-side safety.

**Rex** (University of Erlangen-Nuremberg): A research framework that
replaces the BPF verifier entirely with Rust's compile-time safety. Uses
typed wrappers (`RexHashMap<K,V>`) with RAII resource management. Map lookups
return `Option` values, but the paper does not address the pointer
invalidation problem specifically — it relies on Rust's ownership model
to prevent use-after-free generally, without modeling the "invalidated by
helper call" semantic.

**Verdict**: No existing BPF Rust framework has solved this problem.

### 2.2 Related type system techniques

**GhostCell** (ICFP 2021, Yanovski et al.): Separates data from permission
using a phantom lifetime brand `'brand`. A `GhostToken<'brand>` grants access
to all `GhostCell<'brand, T>` values sharing that brand. The key invariant:
`&GhostToken` gives shared access, `&mut GhostToken` gives exclusive access.
Formally verified via RustBelt in Coq.

**Generativity crate**: Uses a macro (`make_guard!`) to create a `Guard` with
a unique invariant lifetime. The invariance prevents the lifetime from being
coerced to match any other lifetime, providing a branding guarantee. Based on
the same ideas as Haskell's ST monad.

**Session types** (session_types crate): Encode communication protocols at the
type level. Each operation consumes a channel and returns a new channel with
the remaining protocol type. This is linear typing via move semantics. Zero
runtime cost.

**Stack tokens** (Armin Ronacher, 2022): Zero-sized marker types created via
macro, passed as proof parameters to scope reference validity. Alternative to
closure-based scoping that avoids callback nesting. Soundness is debated.

**Crossbeam scope**: `crossbeam::scope(|s| { ... })` creates a scope where
spawned threads must finish before the scope exits. The callback pattern with
caller-chosen lifetime prevents references from escaping.

**Verus** (VMware Research et al., 2023): Formal verification for Rust using
linear ghost types. Ghost types encode resource ownership for verification
without runtime cost. Relevant conceptually but requires a custom verification
tool, not applicable to production BPF code.

## 3. Detailed Analysis of Candidate Patterns

### 3.1 The GhostCell / Branded Lifetime Pattern

**Concept**: Create a `BpfContext<'ctx>` token at BPF program entry. Map
lookups return `MapRef<'ctx, V>` tied to that context. Helper calls consume
the old context and return a new one with a different brand.

```rust
// The context token — zero-sized, carries only a phantom lifetime
struct BpfCtx<'brand>(PhantomData<fn(&'brand ()) -> &'brand ()>);
// Note: fn(&'brand ()) -> &'brand () makes 'brand invariant

// A map value reference branded to a specific context
struct MapRef<'brand, V> {
    ptr: *const V,
    _brand: PhantomData<&'brand V>,
}

impl<V> HashMap<V> {
    fn get<'b>(&self, ctx: &BpfCtx<'b>, key: &u32) -> Option<MapRef<'b, V>> {
        // ... call bpf_map_lookup_elem, return branded reference
    }
}

// Helper call consumes old context, returns new one
// Old MapRef<'old, V> becomes invalid because 'old is dead
fn kick_cpu<'old>(ctx: BpfCtx<'old>, cpu: u32) -> BpfCtx<'???> {
    // Problem: what is the new lifetime?
}
```

**The fundamental problem**: Rust lifetimes are resolved at compile time based
on lexical scope. There is no way to create a "new" lifetime at runtime. The
`BpfCtx<'old>` and the new `BpfCtx<'new>` would need different lifetime
parameters, but Rust's type system cannot generate fresh lifetimes — that's
what the `generativity` crate's macro does, but it creates them at *lexical
scope boundaries*, not at arbitrary points in a function.

You could model this with nested closures:

```rust
fn bpf_program(entry_ctx: BpfCtx<'_>) {
    make_guard!(g1);
    let ctx = BpfCtx::new(&g1);
    let val = map.get(&ctx, &key);
    // use val...

    // To call a helper, we need a new brand:
    make_guard!(g2);
    let ctx2 = kick_cpu(ctx, cpu, &g2);
    // val is now invalid because g1's lifetime doesn't match g2
    // But: val's lifetime is 'g1, which is still alive!
    // The invariance doesn't help because both guards are in scope
}
```

**This doesn't work.** The invariant lifetime prevents coercion between
brands, but it doesn't *invalidate* old references when a new brand is
created. Both `g1` and `g2` are alive simultaneously. `MapRef<'g1, V>` is
still valid as long as `g1` is in scope.

To make invalidation work, you'd need the helper call to *consume* or
*mutably borrow* `g1`, preventing further use of `MapRef<'g1, V>`:

```rust
fn kick_cpu<'old, 'new>(
    ctx: BpfCtx<'old>,         // consumed by move
    guard: &'old mut Guard,    // mutably borrows the guard
    cpu: u32,
    new_guard: &'new Guard,
) -> BpfCtx<'new> { ... }
```

By mutably borrowing `guard` (with lifetime `'old`), any `MapRef<'old, V>`
that borrows from `guard` would be invalidated. But this requires `MapRef`
to actually borrow from the guard:

```rust
struct MapRef<'brand, V> {
    ptr: *const V,
    _brand: PhantomData<&'brand Guard>, // borrows the guard
}
```

And `get()` would need to borrow the guard:

```rust
fn get<'b>(&self, guard: &'b Guard, key: &u32) -> Option<MapRef<'b, V>>
```

Then when `kick_cpu` takes `&'b mut Guard`, the shared borrow in `MapRef`
conflicts with the mutable borrow, and the compiler rejects the program.

**This actually works!** But at severe ergonomic cost:

```rust
fn my_bpf_prog() {
    make_guard!(g1);
    let val = map.get(&g1, &42);
    let x = val.unwrap().field; // copy the value out

    // Must create a new guard for the helper call
    make_guard!(g2);
    kick_cpu(&mut g1, 5, &g2);  // invalidates val
    // val is now dead — compiler enforces this

    let val2 = map.get(&g2, &42);
    // ...
}
```

**Evaluation**:
- **Correctness**: Yes, this is sound
- **Zero-cost**: Yes, guards are ZSTs, `PhantomData` compiles away
- **no_std**: Yes, no allocations
- **Ergonomics**: Poor — every helper call requires a new `make_guard!()`,
  and you must thread guards through the entire program
- **BPF codegen**: The `make_guard!` macro creates local variables for drop
  ordering. This should compile to nothing in BPF (the LLVM BPF backend
  eliminates ZSTs), but needs verification
- **Composability**: Very difficult with `bpf_loop` callbacks — the callback
  would need its own guard chain

### 3.2 The Typestate / Linear Types Pattern (Move Semantics)

**Concept**: Use a token that is consumed (moved) by both map lookups and
helper calls. Map lookups return a reference *and* a new token. Helper calls
consume the token (and any outstanding references with it).

```rust
// The access token — zero-sized
struct Token<const N: u32>;

// Map lookup returns both the value and a proof that we're in a
// "reference-holding" state
fn map_get<const N: u32>(
    token: Token<N>,
    map: &HashMap<V>,
    key: &K,
) -> (Option<&V>, RefToken<N>)

// To call a helper, you must surrender the RefToken, which proves
// you've given up all references
fn helper_call(token: RefToken<N>) -> Token<{N+1}>

// But you can't call a helper while holding a MapRef, because
// RefToken was consumed to create the MapRef
```

**The problem with const generics**: Rust doesn't support `{N+1}` in const
generic position without `generic_const_exprs` (unstable). Even with it, the
proliferating type parameters make this unworkable.

Alternative without const generics — use ownership threading:

```rust
struct Token(());

impl Token {
    fn map_get<V>(&mut self, map: &HashMap<V>, key: &u32) -> Option<&V> {
        // The &mut self prevents calling any other method on Token
        // while the returned reference is alive (borrows self)
        // ...but wait, the reference isn't tied to &mut self
    }
}
```

The problem here is that `&V` returned from `map_get` isn't tied to `&mut
self`. We'd need:

```rust
fn map_get<'a, V>(&'a mut self, map: &HashMap<V>, key: &u32) -> Option<&'a V>
```

Now `&'a V` borrows from `&'a mut self`, so you can't call another `&mut
self` method (like a helper) while holding the reference. **This works!**

```rust
struct Ctx(());

impl Ctx {
    fn map_get<'a, V>(&'a mut self, map: &HashMap<V>, key: &u32) -> Option<&'a V> {
        unsafe {
            let ptr = bpf_map_lookup_elem(map.def.as_ptr(), key as *const _ as _);
            if ptr.is_null() { None }
            else { Some(&*(ptr as *const V)) }
        }
    }

    fn kick_cpu(&mut self, cpu: u32, flags: u64) {
        unsafe { scx_bpf_kick_cpu(cpu, flags) }
    }
}

fn my_bpf_prog(ctx: &mut Ctx) {
    let val = ctx.map_get(&MY_MAP, &42);
    if let Some(v) = val {
        let x = v.field;  // OK: ctx is borrowed
        // ctx.kick_cpu(5, 0);  // COMPILE ERROR: ctx is mutably borrowed by val
    }
    // val is dropped here, ctx is released
    ctx.kick_cpu(5, 0);  // OK: ctx is free
}
```

**This is the simplest correct approach.** The key insight: `&mut Ctx`
is the invariant. You can't call helpers (which need `&mut Ctx`) while
holding references (which borrow `&Ctx` or `&mut Ctx`).

**But there's a subtlety**: If `map_get` takes `&'a mut self` and returns
`&'a V`, then you can't do *two* map lookups simultaneously:

```rust
let val1 = ctx.map_get(&MAP_A, &1);  // borrows ctx mutably
let val2 = ctx.map_get(&MAP_B, &2);  // ERROR: ctx already borrowed
```

This is overly restrictive. You should be able to hold references from two
different maps simultaneously (the verifier allows this). To fix this, use
`&self` instead of `&mut self`:

```rust
fn map_get<'a, V>(&'a self, map: &HashMap<V>, key: &u32) -> Option<&'a V>

fn kick_cpu(&mut self, cpu: u32, flags: u64)
```

Now `map_get` takes `&self` (shared borrow) and `kick_cpu` takes `&mut self`
(exclusive borrow). You can hold multiple `&self` borrows (multiple map refs)
but you can't call `kick_cpu` until all shared borrows are released. This
matches the BPF verifier semantics perfectly.

```rust
fn my_bpf_prog(ctx: &mut Ctx) {
    // Multiple lookups OK — both borrow &ctx
    let val1 = ctx.map_get(&MAP_A, &1);
    let val2 = ctx.map_get(&MAP_B, &2);
    let sum = val1.unwrap().x + val2.unwrap().y;  // OK

    // drop val1, val2 (or let them go out of scope)
    // Now we can call helpers:
    ctx.kick_cpu(5, 0);  // Takes &mut self, OK because no outstanding borrows
}
```

**Evaluation**:
- **Correctness**: Yes — `&self` for reads, `&mut self` for invalidating ops
- **Zero-cost**: Yes — `Ctx` can be zero-sized or contain just the program
  context pointer
- **no_std**: Yes
- **Ergonomics**: Good! Natural Rust borrow-checker patterns, no macros
- **BPF codegen**: `Ctx` compiles away if zero-sized
- **Composability**: Works naturally with closures (the closure captures `ctx`
  by reference). Works with `bpf_loop` if the callback takes `&Ctx` (read
  phase) or `&mut Ctx` (write phase, but no map refs held)

**Limitation**: This relies on the programmer wrapping *all* BPF helpers and
kfuncs in the `Ctx` struct with `&mut self`. Any helper that's accidentally
exposed as a free function bypasses the safety. This is an API design
discipline issue, not a type system limitation.

**Limitation 2**: Mutable map access (`get_ptr_mut`) returns `&mut V`, which
borrows `&mut self`, preventing simultaneous reads. This could be addressed
with interior mutability or by having `get_mut` also take `&self` and return
`&Cell<V>` (since BPF is single-threaded per CPU).

### 3.3 The Callback / Scope Pattern

**Concept**: Similar to `crossbeam::scope`. Map lookups take a closure and
the reference is only valid within the closure.

```rust
impl HashMap<V> {
    fn with_ref<R>(&self, key: &K, f: impl FnOnce(Option<&V>) -> R) -> R {
        let ptr = unsafe { bpf_map_lookup_elem(...) };
        if ptr.is_null() {
            f(None)
        } else {
            f(Some(unsafe { &*ptr }))
        }
    }
}

// Usage:
map.with_ref(&key, |val| {
    if let Some(v) = val {
        let x = v.field;
        // Can't call helpers here... but how is that enforced?
    }
});
```

**The enforcement problem**: Nothing in Rust's type system prevents calling
a BPF helper inside the closure. The closure receives `Option<&V>` and can
call whatever functions it wants. You'd need:

1. **Negative trait bounds** (not stable in Rust): Something like
   `F: FnOnce(&V) + !CanCallHelpers` — doesn't exist

2. **Capability-based restriction**: Only pass a restricted "read context"
   into the closure that doesn't have helper-calling methods:

```rust
struct ReadCtx<'a>(&'a Ctx);
// ReadCtx has map_get but NOT kick_cpu

map.with_ref(&key, |val, read_ctx: &ReadCtx| {
    // read_ctx.kick_cpu(5);  // Doesn't exist on ReadCtx
    // But nothing prevents: unsafe { scx_bpf_kick_cpu(5, 0) }
});
```

This is just a weaker version of approach 3.2 with worse ergonomics (callback
nesting). The callback pattern adds nesting for no additional safety over
the `&self`/`&mut self` split.

**Evaluation**:
- **Correctness**: Partial — can't prevent raw helper calls inside closure
- **Zero-cost**: Yes
- **no_std**: Yes
- **Ergonomics**: Poor — callback nesting, especially with multiple maps
- **Composability**: Poor — nested callbacks compound
- **Verdict**: Strictly worse than approach 3.2

### 3.4 The Two-Phase / Session Types Pattern

**Concept**: Split the BPF program into alternating phases encoded in the
type system. A "reference phase" allows map lookups; a "helper phase" allows
helper calls. Transitions between phases consume the phase token.

```rust
struct RefPhase(());   // Can hold map refs, can't call helpers
struct HelperPhase(()); // Can call helpers, can't hold map refs

impl RefPhase {
    fn map_get<V>(&self, map: &HashMap<V>, key: &u32) -> Option<&V> { ... }

    // Transition to helper phase — consumes self (and invalidates
    // all borrows of self, including map refs)
    fn to_helper_phase(self) -> HelperPhase { HelperPhase(()) }
}

impl HelperPhase {
    fn kick_cpu(&self, cpu: u32) { ... }

    // Transition back to reference phase
    fn to_ref_phase(self) -> RefPhase { RefPhase(()) }
}
```

**Problem**: The phase tokens are consumed by move, but map refs borrow them
by reference. Moving `RefPhase` while borrows exist is a compile error —
which is what we want! But this means *every* transition requires dropping
all map refs first, and the program becomes a state machine:

```rust
fn my_bpf_prog(phase: RefPhase) {
    let val = phase.map_get(&MAP, &42);
    let x = val.unwrap().field;
    drop(val);  // must drop before transition

    let phase = phase.to_helper_phase();  // consumes RefPhase
    phase.kick_cpu(5);

    let phase = phase.to_ref_phase();  // back to ref phase
    let val2 = phase.map_get(&MAP, &42);
    // ...
}
```

**Wait — this is exactly approach 3.2 but with worse API surface.** The
`&self` / `&mut self` split on a single `Ctx` achieves the same effect
without requiring explicit phase transitions. The borrow checker
automatically manages the phases.

In approach 3.2, `&self` = reference phase, `&mut self` = helper phase. The
transitions are implicit via borrow lifetimes.

**Evaluation**:
- **Correctness**: Yes (same as 3.2)
- **Zero-cost**: Yes
- **no_std**: Yes
- **Ergonomics**: Worse than 3.2 — explicit phase transitions are noisy
- **Composability**: Worse than 3.2 — phase tokens must be threaded manually
- **Verdict**: 3.2 subsumes this approach with better ergonomics

### 3.5 The Haskell ST Monad Analogy

In Haskell, the ST monad uses rank-2 polymorphism to prevent mutable
references from escaping a scope:

```haskell
runST :: (forall s. ST s a) -> a
```

The `forall s` means the caller of `runST` cannot choose `s` — it's
universally quantified, so the body must work for *any* `s`. Since `STRef s a`
contains `s`, an `STRef` created inside `runST` cannot escape (its type would
mention the existentially hidden `s`).

In Rust, the analog is higher-rank trait bounds (HRTBs):

```rust
fn with_context<R>(f: impl for<'brand> FnOnce(BpfCtx<'brand>) -> R) -> R {
    f(BpfCtx(PhantomData))
}
```

The `for<'brand>` means `f` must work for any `'brand`. A `MapRef<'brand, V>`
created inside the closure cannot escape (its type mentions `'brand`).

**But this only prevents escape, not invalidation.** Inside the closure, you
can still hold a `MapRef<'brand, V>` while calling a helper. The rank-2
type prevents the reference from *escaping the closure* but doesn't prevent
misuse *within* it.

You could combine this with approach 3.2:

```rust
fn with_context<R>(f: impl for<'brand> FnOnce(&mut BpfCtx<'brand>) -> R) -> R {
    f(&mut BpfCtx(PhantomData))
}
```

Now the closure gets `&mut BpfCtx<'brand>`, and the `&self`/`&mut self` split
enforces invalidation within the closure. But the HRTB doesn't add anything
beyond what 3.2 already provides — the `&mut` borrow on `BpfCtx` is
sufficient.

**The HRTB/generativity approach adds value only if you need multiple
independent scopes** (e.g., nested `runST` calls that create independent
reference pools). For BPF programs, there's only one scope (the program
execution), so this is unnecessary complexity.

**Evaluation**:
- **Correctness**: Same as 3.2
- **Complexity**: Higher than 3.2 for no additional benefit in BPF context
- **Verdict**: Use 3.2 directly; the ST monad pattern is overkill here

## 4. Practical Evaluation Matrix

| Criterion | 3.1 GhostCell | 3.2 Borrow Split | 3.3 Callback | 3.4 Session | 3.5 ST Monad |
|-----------|--------------|-------------------|--------------|-------------|-------------|
| **Correct** | Yes | Yes | Partial | Yes | Yes |
| **no_std** | Yes | Yes | Yes | Yes | Yes |
| **Zero-cost** | Yes | Yes | Yes | Yes | Yes |
| **Ergonomics** | Poor | Good | Poor | Mediocre | Mediocre |
| **Multiple map refs** | Yes | Yes | Hard | Manual | Yes |
| **bpf_loop compat** | Hard | Moderate | Hard | Hard | Hard |
| **Implementation effort** | High | Low | Low | Medium | Medium |
| **Scheduler author UX** | Tedious | Natural | Nested | Explicit | Wrapped |

## 5. Recommendation

### Primary recommendation: Approach 3.2 — The Borrow Split

The `&self` / `&mut self` split on a `BpfCtx` type is the clear winner. It
is:

- **Sound**: Leverages Rust's standard borrow checker, no unsafe tricks
- **Zero-cost**: `BpfCtx` can be a ZST or a thin wrapper around the BPF
  program context
- **Ergonomic**: Uses patterns every Rust programmer already knows
- **Incrementally adoptable**: Can coexist with the existing `unsafe` API
- **Minimal code**: Requires wrapping helpers in methods, not inventing new
  type machinery

Here is a concrete sketch of what the API would look like:

```rust
/// BPF execution context. All BPF operations go through this.
///
/// Map lookups borrow this immutably (&self), so multiple lookups
/// can coexist. Helper/kfunc calls borrow this mutably (&mut self),
/// which prevents them from being called while map references are live.
///
/// This mirrors the BPF verifier's pointer invalidation rule:
/// map value pointers are invalidated by any helper/kfunc call.
pub struct BpfCtx {
    // Could hold the program context (e.g., *mut pt_regs for kprobes,
    // *mut bpf_sched_ext_ops for struct_ops)
    _private: (),
}

impl BpfCtx {
    // --- Map operations (shared borrow — multiple refs can coexist) ---

    /// Look up a value in a HashMap. The returned reference borrows
    /// from `&self`, preventing helper calls until it is dropped.
    pub fn map_get<'a, K, V>(
        &'a self,
        map: &HashMap<K, V>,
        key: &K,
    ) -> Option<&'a V> {
        unsafe { map.get(key) }
    }

    /// Look up a mutable value. Uses &self (not &mut self) because
    /// BPF is single-threaded per-CPU and we want to allow concurrent
    /// lookups. Returns a raw pointer that the caller can write through.
    ///
    /// # Safety
    /// Caller must ensure no aliasing writes to the same key.
    pub unsafe fn map_get_mut<'a, K, V>(
        &'a self,
        map: &HashMap<K, V>,
        key: &K,
    ) -> Option<&'a mut V> {
        // This is sound only on per-CPU maps or with external sync.
        // For shared maps, this should remain unsafe.
        todo!()
    }

    // --- Helper calls (exclusive borrow — invalidates all map refs) ---

    pub fn kick_cpu(&mut self, cpu: u32, flags: u64) {
        unsafe { scx_bpf_kick_cpu(cpu, flags) }
    }

    pub fn bpf_get_smp_processor_id(&mut self) -> u32 {
        unsafe { bpf_get_smp_processor_id() }
    }

    // ... wrap all helpers with &mut self ...

    // --- Non-invalidating operations (shared borrow) ---
    // Some BPF operations don't invalidate map pointers. These can
    // take &self. However, being conservative (&mut self for everything)
    // is safer and simpler. Optimization: identify non-invalidating
    // operations and use &self for them.
}

// Entry point macro generates the BpfCtx:
#[scx_struct_ops]
fn enqueue(ctx: &mut BpfCtx, p: &task_struct, enq_flags: u64) {
    if let Some(tctx) = ctx.map_get(&TASK_CTX, &p.pid) {
        let runtime = tctx.exec_runtime;  // copy out before helper call
        // ctx.kick_cpu(5, 0);  // COMPILE ERROR while tctx is alive
    }
    // tctx dropped — now we can call helpers
    ctx.kick_cpu(5, 0);  // OK
}
```

### The "copy-out" pattern

The most common real-world usage involves:
1. Look up a map entry
2. Read some fields
3. Call a helper with those field values
4. Write back to the map

This naturally works with the borrow split:

```rust
fn enqueue(ctx: &mut BpfCtx, p: &task_struct, enq_flags: u64) {
    // Phase 1: Read
    let (pid, vtime) = {
        let tctx = ctx.map_get(&TASK_CTX, &p.pid);
        match tctx {
            Some(t) => (t.pid, t.vtime),
            None => return,
        }
    }; // tctx dropped here

    // Phase 2: Helper call
    ctx.kick_cpu(cpu, 0);

    // Phase 3: Write back
    ctx.map_insert(&TASK_CTX, &pid, &TaskCtx { vtime: vtime + 1, .. });
}
```

### Which helpers actually invalidate pointers?

An important optimization: not all BPF helpers invalidate map pointers.
The BPF verifier's `check_helper_call` only invalidates references for
helpers that could modify map state or release references. Pure query
helpers (like `bpf_ktime_get_ns()`, `bpf_get_smp_processor_id()`) do
not invalidate pointers.

We could classify helpers:

```rust
impl BpfCtx {
    // Non-invalidating: safe to call while holding map refs
    pub fn ktime_get_ns(&self) -> u64 { ... }
    pub fn get_smp_processor_id(&self) -> u32 { ... }

    // Invalidating: requires &mut self
    pub fn kick_cpu(&mut self, cpu: u32, flags: u64) { ... }
    pub fn map_insert<K, V>(&mut self, map: &HashMap<K,V>, ...) { ... }
    pub fn bpf_task_release(&mut self, task: *mut task_struct) { ... }
}
```

This would be more ergonomic (fewer forced drops) but requires careful
auditing of which helpers are truly non-invalidating. **The conservative
approach (everything is `&mut self`) is correct by default; the optimization
can be applied incrementally.**

### What about mutable map access?

The `&self`/`&mut self` split has a tension with mutable map access:

```rust
// This would need &mut self to prevent aliased mutation...
fn map_get_mut(&mut self, ...) -> Option<&mut V>

// But then you can't hold two mutable refs, or even a read + write
let a = ctx.map_get_mut(&MAP, &1);     // borrows ctx mutably
let b = ctx.map_get(&OTHER_MAP, &2);   // ERROR: ctx already borrowed
```

**Resolution**: In BPF, map access is inherently racy (no locks by default).
The verifier doesn't prevent concurrent writes from different CPUs. So the
"safety" of `&mut V` is already a fiction. Options:

1. **Keep `get_ptr_mut` as unsafe**, returning `*mut V` — honest about the
   aliasing risk
2. **Use `Cell<V>` or `UnsafeCell<V>`** — allows mutation through `&self`
   with no aliasing guarantees (matches BPF semantics)
3. **For per-CPU maps**: `&mut V` through `&self` is actually safe (no cross-
   CPU aliasing). Use a `PerCpuRef<V>` wrapper with `DerefMut`

### What about `bpf_loop` and callbacks?

`bpf_loop(count, callback, ctx, flags)` calls `callback` up to `count` times.
The callback receives a user-provided context pointer.

With the borrow split, the callback would receive either `&BpfCtx` (read-only,
can hold map refs within each iteration) or `&mut BpfCtx` (can call helpers,
but no map refs across helper calls):

```rust
ctx.bpf_loop(10, |ctx: &mut BpfCtx, i: u32| {
    let val = ctx.map_get(&MAP, &i);
    // use val...
    drop(val);
    ctx.kick_cpu(i, 0);
    LoopControl::Continue
});
```

This works naturally because each closure invocation gets a fresh `&mut BpfCtx`
borrow.

## 6. Open Questions

### 6.1 Does `PhantomData` / ZST code survive BPF compilation?

The LLVM BPF backend should eliminate zero-sized types entirely, producing
no additional instructions. But this needs verification with actual BPF
programs. Specifically:

- Do ZST function parameters get eliminated?
- Does `PhantomData` in struct fields affect BPF struct layout?
- Does the borrow checker's lifetime tracking generate any debug info that
  inflates BPF object size?

### 6.2 Can the verifier cope with the generated code?

The borrow checker might force certain code patterns (e.g., explicit drops,
temporaries) that generate BPF instructions the verifier doesn't like. The
verifier is notoriously sensitive to code shape. Testing with real schedulers
is essential.

### 6.3 Which helpers are truly non-invalidating?

A systematic audit of BPF helpers is needed to classify them as invalidating
vs non-invalidating. The kernel source (`check_helper_call` in
`kernel/bpf/verifier.c`) is the authority, but it's complex and version-
dependent.

For a first implementation, treat all helpers as invalidating (`&mut self`).
Relax individual helpers to `&self` only after verifying they're safe.

### 6.4 How does this interact with struct_ops callback signatures?

The BPF struct_ops callbacks have fixed signatures defined by the kernel.
The Rust entry point must bridge from the kernel's ABI to the safe API:

```rust
// Kernel expects: void (*enqueue)(struct task_struct *p, u64 enq_flags)
// We generate:
#[no_mangle]
unsafe extern "C" fn enqueue(p: *mut task_struct, enq_flags: u64) {
    let mut ctx = BpfCtx::new();
    safe_enqueue(&mut ctx, unsafe { &*p }, enq_flags);
}

fn safe_enqueue(ctx: &mut BpfCtx, p: &task_struct, enq_flags: u64) {
    // Safe code here — ctx enforces pointer validity
}
```

This requires a thin `unsafe` entry shim per callback, which is acceptable.

### 6.5 What about `task_struct` pointers?

The `task_struct *` pointer in struct_ops callbacks has its own validity rules
(it's valid for the duration of the callback, guarded by RCU). This is
separate from map pointer validity and could be modeled with a simple
lifetime tied to the callback function signature.

### 6.6 Is the ergonomic cost acceptable?

The "copy out, drop ref, call helper" pattern adds a few lines vs the current
unsafe code. Real scheduler code (like scx_rlfifo) already follows this
pattern naturally in C — the BPF verifier forces it. The Rust API would just
make the compiler enforce what the verifier enforces, catching errors at
compile time instead of BPF load time.

For scheduler authors migrating from C, the explicit "drop before helper"
pattern is actually *less* surprising than the C verifier errors they're
used to debugging.

### 6.7 Should this be in aya-ebpf or a separate crate?

The `BpfCtx` wrapper could be:
- **In aya-ebpf itself**: Requires significant refactoring of the helper API
- **In a separate `aya-ebpf-safe` crate**: Wraps `aya-ebpf` with the safe API,
  allows gradual adoption
- **In a scheduler-specific crate** (e.g., `scx-ebpf`): Tailored to struct_ops
  patterns

Starting with a separate wrapper crate is lowest risk.

## 7. Summary

The "borrow split" pattern (Section 3.2) is the recommended approach. It:

1. Uses `&self` for map lookups (allows multiple concurrent references)
2. Uses `&mut self` for helper/kfunc calls (forces reference drops first)
3. Requires no macros, no phantom types, no branded lifetimes
4. Is zero-cost (compiles away completely)
5. Works in `#![no_std]` with no allocator
6. Matches the BPF verifier's actual semantics
7. Is incrementally adoptable alongside the existing unsafe API

The other patterns (GhostCell, session types, ST monad) are more
theoretically interesting but add complexity without additional safety
in the BPF context. The borrow checker already provides exactly the
right level of enforcement when the API is designed with the
`&self`/`&mut self` split.

The pragmatic approach is: **design the API so the borrow checker does
the work the verifier does, then let unsafe code handle the rest.**
Perfect safety (preventing all possible misuse) is not achievable without
unacceptable ergonomic cost or language features Rust doesn't have. But
the borrow split catches the most common class of errors (use-after-
invalidation) at zero cost, which is a significant improvement over the
current "everything is unsafe" status quo.
