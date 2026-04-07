# Containerfile for scx_cosmos_rs
#
# Two usage modes:
#
# 1. Pre-built binary (fast, works behind corporate firewalls):
#    make build
#    make container
#
# 2. Full build inside container (requires internet access):
#    podman build --target=builder -t scx_cosmos_rs_build .
#
# The default target copies a pre-built binary from the host.
# Build the binary first with: make build

FROM fedora:latest

COPY scx/scheds/rust_only/scx_cosmos/target/release/scx_cosmos_rs \
    /usr/local/bin/scx_cosmos_rs

ENTRYPOINT ["/usr/local/bin/scx_cosmos_rs"]
