# Build stage: compile the pure-Rust cosmos scheduler
FROM rust:latest AS builder

# Install system deps (clang for BPF, bpftool for vmlinux BTF extraction)
RUN apt-get update && apt-get install -y \
    clang \
    libclang-dev \
    bpftool \
    && rm -rf /var/lib/apt/lists/*

# Install Rust nightly + BPF toolchain
RUN rustup toolchain install nightly \
    && rustup component add rust-src --toolchain nightly \
    && cargo install bpf-linker

WORKDIR /build

# Copy host vmlinux BTF for eBPF build (extracted before container build)
COPY vmlinux /build/vmlinux

# Copy source trees (aya + scx)
COPY aya/ aya/
COPY scx/ scx/

# Build the scheduler using the copied vmlinux BTF
WORKDIR /build/scx/scheds/rust_only/scx_cosmos
RUN SCX_VMLINUX_BTF=/build/vmlinux cargo build --release

# Runtime stage: minimal image with just the binary
FROM debian:bookworm-slim

COPY --from=builder \
    /build/scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos_rs \
    /usr/local/bin/scx_cosmos_rs

ENTRYPOINT ["/usr/local/bin/scx_cosmos_rs"]
