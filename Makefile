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

# Auto-detect kernel version for feature flags
KERN_VER := $(shell uname -r | cut -d. -f1-2)
KERN_MAJOR := $(shell echo $(KERN_VER) | cut -d. -f1)
KERN_MINOR := $(shell echo $(KERN_VER) | cut -d. -f2)
IS_6_16_PLUS := $(shell [ "$(KERN_MAJOR)" -gt 6 ] 2>/dev/null && echo 1 || ([ "$(KERN_MAJOR)" -eq 6 ] && [ "$(KERN_MINOR)" -ge 16 ] 2>/dev/null && echo 1 || echo 0))

# Resolve vmlinux BTF: prefer /lib/modules/.../build/vmlinux, fall back to /sys/kernel/btf/vmlinux
VMLINUX_BTF := $(shell \
	p="/lib/modules/$$(uname -r)/build/vmlinux"; \
	if [ -f "$$p" ]; then echo "$$p"; \
	elif [ -f /sys/kernel/btf/vmlinux ]; then echo /sys/kernel/btf/vmlinux; \
	fi)

FEATURES := $(if $(filter 1,$(IS_6_16_PLUS)),--features kernel_6_16,)

build: ## Build the pure-Rust cosmos scheduler (auto-detects kernel 6.16+)
	cd $(COSMOS_DIR) && SCX_VMLINUX_BTF=$(VMLINUX_BTF) cargo build --release $(FEATURES)
	@echo ""
	@echo "Binary: $(BINARY)"

build-6.16: ## Build for kernel 6.16+ (enables select_cpu_and kfunc)
	cd $(COSMOS_DIR) && SCX_VMLINUX_BTF=$(VMLINUX_BTF) \
		cargo build --release --features kernel_6_16

test: build ## Build and run cosmos on this host (30s, requires sudo)
	./test_cosmos.sh 30

test-vm: build ## Build and run cosmos in a virtme-ng VM (30s)
	./test_cosmos_vm.sh 30

container: ## Build a container image with the cosmos scheduler
	@echo "=== Extracting vmlinux BTF for container build ==="
	@cp /sys/kernel/btf/vmlinux vmlinux
	podman build -t scx_cosmos_rs .
	@rm -f vmlinux

clean: ## Clean build artifacts
	cd $(COSMOS_DIR) && cargo clean
