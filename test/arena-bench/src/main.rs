//! Benchmark harness for aya-arena-common data structures.
//!
//! Tests allocation speed, memory efficiency, and linked-list operations
//! for the arena bump allocator and shared types, comparing against
//! std::collections::LinkedList as a baseline.

use std::collections::LinkedList;
use std::time::{Duration, Instant};

use aya_arena_common::{
    ArenaBumpState, ArenaListHead, ArenaNodeHeader, ArenaPtr,
    CounterNode, LabelNode, TAG_COUNTER, TAG_LABEL,
};

// ── Configuration ──────────────────────────────────────────────────────

const ARENA_SIZE: usize = 64 * 1024 * 1024; // 64 MiB
const SMALL_ALLOC: u64 = 24;   // CounterNode size
const MEDIUM_ALLOC: u64 = 56;  // LabelNode size
const LARGE_ALLOC: u64 = 256;
const WARMUP_ITERS: usize = 3;
const BENCH_ITERS: usize = 5;

// ── Simulated arena (mmap-backed) ──────────────────────────────────────

struct SimulatedArena {
    memory: Vec<u8>,
    bump: ArenaBumpState,
}

impl SimulatedArena {
    fn new(size: usize) -> Self {
        Self {
            memory: vec![0u8; size],
            bump: ArenaBumpState::new(size as u64),
        }
    }

    fn base(&mut self) -> *mut u8 {
        self.memory.as_mut_ptr()
    }

    fn alloc<T>(&mut self) -> Option<*mut T> {
        let size = std::mem::size_of::<T>() as u64;
        let align = std::mem::align_of::<T>() as u64;
        let offset = self.bump.alloc(size, align)?;
        Some(unsafe { self.memory.as_mut_ptr().add(offset as usize).cast() })
    }

    fn alloc_raw(&mut self, size: u64, align: u64) -> Option<u64> {
        self.bump.alloc(size, align)
    }

    fn reset(&mut self) {
        self.bump.reset();
        // Zero only the used portion for reproducibility
        let used = self.bump.watermark as usize;
        if used > 0 {
            self.memory[..used].fill(0);
        }
    }

    fn watermark(&self) -> u64 {
        self.bump.watermark
    }

    fn capacity(&self) -> u64 {
        self.bump.capacity
    }

    fn utilization_pct(&self) -> f64 {
        if self.bump.capacity == 0 {
            return 0.0;
        }
        100.0 * self.bump.watermark as f64 / self.bump.capacity as f64
    }
}

// ── Benchmark result ───────────────────────────────────────────────────

struct BenchResult {
    name: String,
    count: usize,
    total: Duration,
    per_op: Duration,
    throughput: f64, // ops/sec
    extra: String,
}

impl BenchResult {
    fn new(name: &str, count: usize, total: Duration, extra: &str) -> Self {
        let per_op = total / count as u32;
        let throughput = count as f64 / total.as_secs_f64();
        Self {
            name: name.to_string(),
            count,
            total,
            per_op,
            throughput,
            extra: extra.to_string(),
        }
    }

    fn print(&self) {
        println!(
            "  {:<45} {:>8} ops  {:>10.2}ms  {:>6.0} ns/op  {:>10.0} ops/s{}",
            self.name,
            self.count,
            self.total.as_secs_f64() * 1000.0,
            self.per_op.as_nanos(),
            self.throughput,
            if self.extra.is_empty() {
                String::new()
            } else {
                format!("  {}", self.extra)
            },
        );
    }
}

// ── Run a benchmark N times, return median ─────────────────────────────

fn run_bench<F: FnMut() -> BenchResult>(name: &str, mut f: F) -> BenchResult {
    // Warmup
    for _ in 0..WARMUP_ITERS {
        f();
    }

    let mut results: Vec<Duration> = Vec::with_capacity(BENCH_ITERS);
    let mut last_result = None;
    for _ in 0..BENCH_ITERS {
        let r = f();
        results.push(r.total);
        last_result = Some(r);
    }
    results.sort();
    let median = results[BENCH_ITERS / 2];

    let mut r = last_result.unwrap();
    r.total = median;
    r.per_op = median / r.count as u32;
    r.throughput = r.count as f64 / median.as_secs_f64();
    r.name = name.to_string();
    r
}

// ── Benchmark: raw allocation speed ────────────────────────────────────

fn bench_alloc_speed(alloc_size: u64, align: u64, label: &str) -> BenchResult {
    run_bench(
        &format!("bump_alloc({}B, align={})", alloc_size, align),
        || {
            let mut arena = SimulatedArena::new(ARENA_SIZE);
            let mut count = 0usize;
            let start = Instant::now();
            while arena.alloc_raw(alloc_size, align).is_some() {
                count += 1;
            }
            let elapsed = start.elapsed();
            BenchResult::new(
                label,
                count,
                elapsed,
                &format!(
                    "util={:.1}%",
                    arena.utilization_pct()
                ),
            )
        },
    )
}

// ── Benchmark: allocation + init (CounterNode) ─────────────────────────

fn bench_counter_node_alloc(n: usize) -> BenchResult {
    run_bench("alloc+init CounterNode", || {
        let mut arena = SimulatedArena::new(ARENA_SIZE);
        let start = Instant::now();
        for i in 0..n {
            if let Some(ptr) = arena.alloc::<CounterNode>() {
                unsafe {
                    ptr.write(CounterNode::new(i as u64));
                }
            } else {
                break;
            }
        }
        let elapsed = start.elapsed();
        BenchResult::new(
            "alloc+init CounterNode",
            n,
            elapsed,
            &format!("used={}KB", arena.watermark() / 1024),
        )
    })
}

// ── Benchmark: allocation + init (LabelNode) ───────────────────────────

fn bench_label_node_alloc(n: usize) -> BenchResult {
    run_bench("alloc+init LabelNode", || {
        let mut arena = SimulatedArena::new(ARENA_SIZE);
        let label = b"benchmark-label-data";
        let start = Instant::now();
        for _ in 0..n {
            if let Some(ptr) = arena.alloc::<LabelNode>() {
                unsafe {
                    ptr.write(LabelNode::new(label));
                }
            } else {
                break;
            }
        }
        let elapsed = start.elapsed();
        BenchResult::new(
            "alloc+init LabelNode",
            n,
            elapsed,
            &format!("used={}KB", arena.watermark() / 1024),
        )
    })
}

// ── Benchmark: arena linked list (insert N, traverse all) ──────────────

fn bench_arena_linked_list(n: usize) -> (BenchResult, BenchResult) {
    // Insert
    let insert_result = run_bench("arena list: insert N CounterNodes", || {
        let mut arena = SimulatedArena::new(ARENA_SIZE);
        let base = arena.base();

        // Reserve space for list head at offset 0
        let head_offset = arena.alloc_raw(
            std::mem::size_of::<ArenaListHead>() as u64,
            std::mem::align_of::<ArenaListHead>() as u64,
        )
        .unwrap();
        let head_ptr = unsafe { base.add(head_offset as usize) as *mut ArenaListHead };
        unsafe {
            (*head_ptr).head = ArenaPtr::null();
            (*head_ptr).count = 0;
        }

        let start = Instant::now();
        for i in 0..n {
            let node_ptr = match arena.alloc::<CounterNode>() {
                Some(p) => p,
                None => break,
            };
            let base = arena.base();
            unsafe {
                (*node_ptr) = CounterNode::new(i as u64);
                // Prepend to list
                (*node_ptr).header.next = (*head_ptr).head;
                (*head_ptr).head = ArenaPtr::from_raw(
                    node_ptr as *mut ArenaNodeHeader,
                    base,
                );
                (*head_ptr).count += 1;
            }
        }
        let elapsed = start.elapsed();
        BenchResult::new(
            "arena list: insert",
            n,
            elapsed,
            &format!("used={}KB", arena.watermark() / 1024),
        )
    });

    // Traverse (build list first, then time traversal)
    let traverse_result = run_bench("arena list: traverse N nodes", || {
        let mut arena = SimulatedArena::new(ARENA_SIZE);
        let base = arena.base();

        let head_offset = arena.alloc_raw(
            std::mem::size_of::<ArenaListHead>() as u64,
            std::mem::align_of::<ArenaListHead>() as u64,
        )
        .unwrap();
        let head_ptr = unsafe { base.add(head_offset as usize) as *mut ArenaListHead };
        unsafe {
            (*head_ptr).head = ArenaPtr::null();
            (*head_ptr).count = 0;
        }

        // Build list
        for i in 0..n {
            let node_ptr = match arena.alloc::<CounterNode>() {
                Some(p) => p,
                None => break,
            };
            let base = arena.base();
            unsafe {
                (*node_ptr) = CounterNode::new(i as u64);
                (*node_ptr).header.next = (*head_ptr).head;
                (*head_ptr).head = ArenaPtr::from_raw(
                    node_ptr as *mut ArenaNodeHeader,
                    base,
                );
                (*head_ptr).count += 1;
            }
        }

        // Traverse
        let base = arena.base();
        let start = Instant::now();
        let mut sum = 0u64;
        let mut current = unsafe { (*head_ptr).head };
        let mut traversed = 0usize;
        while !current.is_null() {
            let node = unsafe { current.resolve(base) };
            if node.is_null() {
                break;
            }
            let counter = node as *const CounterNode;
            sum += unsafe { (*counter).value };
            current = unsafe { (*node).next };
            traversed += 1;
        }
        let elapsed = start.elapsed();
        // Use sum to prevent optimization
        let _ = std::hint::black_box(sum);
        BenchResult::new(
            "arena list: traverse",
            traversed,
            elapsed,
            "",
        )
    });

    (insert_result, traverse_result)
}

// ── Benchmark: std::LinkedList baseline ────────────────────────────────

fn bench_std_linked_list(n: usize) -> (BenchResult, BenchResult) {
    let insert_result = run_bench("std LinkedList: insert N u64", || {
        let mut list = LinkedList::new();
        let start = Instant::now();
        for i in 0..n {
            list.push_front(i as u64);
        }
        let elapsed = start.elapsed();
        BenchResult::new("std list: insert", n, elapsed, "")
    });

    let traverse_result = run_bench("std LinkedList: traverse N nodes", || {
        let mut list = LinkedList::new();
        for i in 0..n {
            list.push_front(i as u64);
        }

        let start = Instant::now();
        let mut sum = 0u64;
        let mut count = 0usize;
        for &val in list.iter() {
            sum += val;
            count += 1;
        }
        let elapsed = start.elapsed();
        let _ = std::hint::black_box(sum);
        BenchResult::new("std list: traverse", count, elapsed, "")
    });

    (insert_result, traverse_result)
}

// ── Benchmark: memory efficiency ───────────────────────────────────────

fn bench_memory_efficiency() {
    println!("\n=== Memory Efficiency ===\n");

    // Measure overhead for different allocation sizes
    let sizes: &[(u64, &str)] = &[
        (8, "8B (tiny)"),
        (24, "24B (CounterNode)"),
        (56, "56B (LabelNode)"),
        (64, "64B (cacheline)"),
        (256, "256B"),
        (1024, "1KB"),
        (4096, "4KB (page)"),
    ];

    println!(
        "  {:<25} {:>10} {:>10} {:>10} {:>10}",
        "Alloc Size", "Count", "Watermark", "Ideal", "Overhead%"
    );
    println!("  {}", "-".repeat(70));

    for &(size, label) in sizes {
        let mut arena = SimulatedArena::new(ARENA_SIZE);
        let mut count = 0usize;
        while arena.alloc_raw(size, 8).is_some() {
            count += 1;
        }
        let watermark = arena.watermark();
        let ideal = count as u64 * size;
        let overhead_pct = if ideal > 0 {
            100.0 * (watermark - ideal) as f64 / ideal as f64
        } else {
            0.0
        };
        println!(
            "  {:<25} {:>10} {:>9}KB {:>9}KB {:>9.1}%",
            label,
            count,
            watermark / 1024,
            ideal / 1024,
            overhead_pct,
        );
    }
}

// ── Benchmark: ArenaPtr resolve() cost ─────────────────────────────────

fn bench_arena_ptr_resolve(n: usize) -> BenchResult {
    run_bench("ArenaPtr::resolve()", || {
        let mut arena = SimulatedArena::new(ARENA_SIZE);
        let base = arena.base();

        // Pre-allocate pointers
        let mut ptrs: Vec<ArenaPtr<CounterNode>> = Vec::with_capacity(n);
        for _ in 0..n {
            if let Some(ptr) = arena.alloc::<CounterNode>() {
                ptrs.push(ArenaPtr::from_raw(ptr, base));
            }
        }
        let base = arena.base();

        let start = Instant::now();
        let mut sum = 0u64;
        for p in &ptrs {
            let raw = unsafe { p.resolve(base) };
            if !raw.is_null() {
                sum += unsafe { (*raw).value };
            }
        }
        let elapsed = start.elapsed();
        let _ = std::hint::black_box(sum);
        BenchResult::new("ArenaPtr::resolve()", ptrs.len(), elapsed, "")
    })
}

// ── Benchmark: mixed-type heterogeneous list ───────────────────────────

fn bench_heterogeneous_list(n: usize) -> BenchResult {
    run_bench("heterogeneous list: traverse mixed types", || {
        let mut arena = SimulatedArena::new(ARENA_SIZE);
        let base = arena.base();

        let head_offset = arena.alloc_raw(
            std::mem::size_of::<ArenaListHead>() as u64,
            std::mem::align_of::<ArenaListHead>() as u64,
        )
        .unwrap();
        let head_ptr = unsafe { base.add(head_offset as usize) as *mut ArenaListHead };
        unsafe {
            (*head_ptr).head = ArenaPtr::null();
            (*head_ptr).count = 0;
        }

        // Build mixed list: alternate CounterNode and LabelNode
        for i in 0..n {
            let base = arena.base();
            if i % 2 == 0 {
                let ptr = match arena.alloc::<CounterNode>() {
                    Some(p) => p,
                    None => break,
                };
                unsafe {
                    (*ptr) = CounterNode::new(i as u64);
                    (*ptr).header.next = (*head_ptr).head;
                    (*head_ptr).head = ArenaPtr::from_raw(ptr as *mut ArenaNodeHeader, base);
                    (*head_ptr).count += 1;
                }
            } else {
                let ptr = match arena.alloc::<LabelNode>() {
                    Some(p) => p,
                    None => break,
                };
                unsafe {
                    (*ptr) = LabelNode::new(b"bench");
                    (*ptr).header.next = (*head_ptr).head;
                    (*head_ptr).head = ArenaPtr::from_raw(ptr as *mut ArenaNodeHeader, base);
                    (*head_ptr).count += 1;
                }
            }
        }

        // Traverse and dispatch by tag
        let base = arena.base();
        let start = Instant::now();
        let mut counter_sum = 0u64;
        let mut label_count = 0u64;
        let mut current = unsafe { (*head_ptr).head };
        let mut traversed = 0usize;
        while !current.is_null() {
            let node = unsafe { current.resolve(base) };
            if node.is_null() {
                break;
            }
            let tag = unsafe { (*node).tag };
            match tag {
                TAG_COUNTER => {
                    counter_sum += unsafe { (*(node as *const CounterNode)).value };
                }
                TAG_LABEL => {
                    label_count += 1;
                }
                _ => {}
            }
            current = unsafe { (*node).next };
            traversed += 1;
        }
        let elapsed = start.elapsed();
        let _ = std::hint::black_box((counter_sum, label_count));
        BenchResult::new("hetero list: traverse", traversed, elapsed, "")
    })
}

// ── Main ───────────────────────────────────────────────────────────────

fn main() {
    println!("=== Arena Benchmark Suite ===");
    println!("Arena size: {} MiB", ARENA_SIZE / (1024 * 1024));
    println!("Iterations per bench: {} (warmup: {})", BENCH_ITERS, WARMUP_ITERS);
    println!();

    // ── Type layout info ──────────────────────────────────────────────
    println!("=== Type Layouts ===\n");
    println!(
        "  ArenaPtr<T>:       size={:>2}  align={:>2}",
        std::mem::size_of::<ArenaPtr<u32>>(),
        std::mem::align_of::<ArenaPtr<u32>>(),
    );
    println!(
        "  ArenaNodeHeader:   size={:>2}  align={:>2}",
        std::mem::size_of::<ArenaNodeHeader>(),
        std::mem::align_of::<ArenaNodeHeader>(),
    );
    println!(
        "  CounterNode:       size={:>2}  align={:>2}",
        std::mem::size_of::<CounterNode>(),
        std::mem::align_of::<CounterNode>(),
    );
    println!(
        "  LabelNode:         size={:>2}  align={:>2}",
        std::mem::size_of::<LabelNode>(),
        std::mem::align_of::<LabelNode>(),
    );
    println!(
        "  ArenaListHead:     size={:>2}  align={:>2}",
        std::mem::size_of::<ArenaListHead>(),
        std::mem::align_of::<ArenaListHead>(),
    );
    println!(
        "  ArenaBumpState:    size={:>2}  align={:>2}",
        std::mem::size_of::<ArenaBumpState>(),
        std::mem::align_of::<ArenaBumpState>(),
    );

    // ── Allocation speed ──────────────────────────────────────────────
    println!("\n=== Allocation Speed (fill 64MiB arena) ===\n");

    bench_alloc_speed(SMALL_ALLOC, 8, "small").print();
    bench_alloc_speed(MEDIUM_ALLOC, 8, "medium").print();
    bench_alloc_speed(LARGE_ALLOC, 8, "large").print();
    bench_alloc_speed(4096, 4096, "page-aligned").print();

    // ── Typed allocation + init ───────────────────────────────────────
    println!("\n=== Typed Alloc+Init ===\n");

    let node_counts = [100_000, 500_000, 1_000_000];
    for &n in &node_counts {
        bench_counter_node_alloc(n).print();
    }
    println!();
    for &n in &node_counts {
        bench_label_node_alloc(n).print();
    }

    // ── Memory efficiency ─────────────────────────────────────────────
    bench_memory_efficiency();

    // ── ArenaPtr resolve ──────────────────────────────────────────────
    println!("\n=== ArenaPtr::resolve() ===\n");
    bench_arena_ptr_resolve(1_000_000).print();

    // ── Linked list comparison ────────────────────────────────────────
    println!("\n=== Linked List: Arena vs std::LinkedList ===\n");

    let list_sizes = [10_000, 100_000, 500_000];
    for &n in &list_sizes {
        println!("  --- n={} ---", n);
        let (arena_ins, arena_trav) = bench_arena_linked_list(n);
        let (std_ins, std_trav) = bench_std_linked_list(n);
        arena_ins.print();
        std_ins.print();
        let ins_ratio = std_ins.per_op.as_nanos() as f64 / arena_ins.per_op.as_nanos() as f64;
        println!("    insert speedup: {:.1}x", ins_ratio);
        println!();
        arena_trav.print();
        std_trav.print();
        let trav_ratio = std_trav.per_op.as_nanos() as f64 / arena_trav.per_op.as_nanos() as f64;
        println!("    traverse speedup: {:.1}x", trav_ratio);
        println!();
    }

    // ── Heterogeneous list ────────────────────────────────────────────
    println!("=== Heterogeneous List (mixed CounterNode + LabelNode) ===\n");
    bench_heterogeneous_list(100_000).print();
    bench_heterogeneous_list(500_000).print();

    println!("\n=== Done ===");
}
