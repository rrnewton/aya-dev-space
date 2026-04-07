.PHONY: build test test-vm install-deps clean help

COSMOS_DIR := scx/scheds/rust_only/scx_cosmos
BINARY := $(COSMOS_DIR)/target/release/scx_cosmos_rs

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install-deps: ## Install build dependencies (Rust nightly, bpf-linker, clang)
	@echo "=== Installing Rust nightly toolchain ==="
	rustup toolchain install nightly-x86_64-unknown-linux-gnu
	rustup component add rust-src --toolchain nightly-x86_64-unknown-linux-gnu
	@echo ""
	@echo "=== Installing bpf-linker ==="
	cargo install bpf-linker
	@echo ""
	@echo "=== Installing system packages (clang) ==="
	@if command -v dnf >/dev/null 2>&1; then \
		sudo dnf install -y clang-libs clang-devel; \
	elif command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get install -y clang libclang-dev; \
	elif command -v pacman >/dev/null 2>&1; then \
		sudo pacman -S --noconfirm clang; \
	else \
		echo "Unknown package manager. Please install clang manually."; \
	fi
	@echo ""
	@echo "=== Dependencies installed ==="

build: ## Build the pure-Rust cosmos scheduler
	cd $(COSMOS_DIR) && cargo build --release
	@echo ""
	@echo "Binary: $(BINARY)"

build-6.16: ## Build for kernel 6.16+ (enables select_cpu_and kfunc)
	cd $(COSMOS_DIR) && SCX_VMLINUX_BTF=/lib/modules/$$(ls /lib/modules/ | grep '^6\.1[6-9]\|^6\.[2-9]\|^7\.' | head -1)/build/vmlinux \
		cargo build --release --features kernel_6_16

test: build ## Build and run cosmos on this host (30s, requires sudo)
	./test_cosmos.sh 30

test-vm: build ## Build and run cosmos in a virtme-ng VM (30s)
	./test_cosmos_vm.sh 30

container: build ## Build container image and extract scx_cosmos_rs binary
	podman build -t scx_cosmos_rs .
	podman create --name scx_cosmos_rs_tmp scx_cosmos_rs
	podman cp scx_cosmos_rs_tmp:/usr/local/bin/scx_cosmos_rs ./scx_cosmos_rs
	podman rm scx_cosmos_rs_tmp
	@echo ""
	@echo "=== Binary extracted ==="
	@ls -lh ./scx_cosmos_rs
	@echo "Run with: sudo ./scx_cosmos_rs"

clean: ## Clean build artifacts
	cd $(COSMOS_DIR) && cargo clean
