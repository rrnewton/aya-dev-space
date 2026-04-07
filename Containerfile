# Build stage: compile the pure-Rust cosmos scheduler
FROM rust:latest AS builder

# Install system deps
RUN apt-get update && apt-get install -y \
    clang \
    libclang-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Rust nightly + BPF toolchain
RUN rustup toolchain install nightly \
    && rustup component add rust-src --toolchain nightly \
    && cargo install bpf-linker

WORKDIR /build

# Copy source trees (aya + scx)
COPY aya/ aya/
COPY scx/ scx/

# Build the scheduler
WORKDIR /build/scx/scheds/rust_only/scx_cosmos
RUN cargo build --release

# Runtime stage: minimal image with just the binary
FROM debian:bookworm-slim

COPY --from=builder \
    /build/scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos_rs \
    /usr/local/bin/scx_cosmos_rs

ENTRYPOINT ["/usr/local/bin/scx_cosmos_rs"]
