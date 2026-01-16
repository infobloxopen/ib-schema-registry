# =============================================================================
# Infoblox Schema Registry - Multi-Architecture Container Build
# =============================================================================
# Documentation: See README.md and specs/001-schema-registry-image/
# Constitution: .specify/memory/constitution.md

# -----------------------------------------------------------------------------
# Configuration Variables
# -----------------------------------------------------------------------------

# Container image name and tag
IMAGE ?= ib-schema-registry
TAG ?= latest

# Base images (Chainguard JRE default for security, Maven for builder compatibility)
BUILDER_IMAGE ?= maven:3-eclipse-temurin-17
RUNTIME_IMAGE ?= cgr.dev/chainguard/jre:latest

# Multi-architecture platforms
PLATFORMS ?= linux/amd64,linux/arm64

# Detect native platform for local builds
NATIVE_ARCH := $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
NATIVE_PLATFORM := linux/$(NATIVE_ARCH)

# Version metadata (extracted from git and submodule)
VERSION ?= $(shell cd upstream/schema-registry 2>/dev/null && git describe --tags --abbrev=0 2>/dev/null || echo "dev")
LOCAL_VERSION ?= $(VERSION)+infoblox.1
REVISION := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
CREATED := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# Docker build arguments
BUILD_ARGS := --build-arg BUILDER_IMAGE=$(BUILDER_IMAGE) \
              --build-arg RUNTIME_IMAGE=$(RUNTIME_IMAGE) \
              --build-arg VERSION=$(LOCAL_VERSION) \
              --build-arg REVISION=$(REVISION) \
              --build-arg CREATED=$(CREATED)

# -----------------------------------------------------------------------------
# Targets
# -----------------------------------------------------------------------------

.DEFAULT_GOAL := help

.PHONY: help
help: ## Display available targets
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║  Infoblox Schema Registry - Multi-Architecture Build         ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration:"
	@echo "  IMAGE=$(IMAGE)"
	@echo "  TAG=$(TAG)"
	@echo "  VERSION=$(LOCAL_VERSION)"
	@echo "  NATIVE_PLATFORM=$(NATIVE_PLATFORM)"
	@echo ""
	@echo "Base Images:"
	@echo "  BUILDER_IMAGE=$(BUILDER_IMAGE)"
	@echo "  RUNTIME_IMAGE=$(RUNTIME_IMAGE)"
	@echo ""
	@echo "Examples:"
	@echo "  make build                          # Build for native platform"
	@echo "  make buildx                         # Build for all platforms"
	@echo "  make build RUNTIME_IMAGE=eclipse-temurin:17-jre  # Temurin alternative"
	@echo "  make push IMAGE=ghcr.io/infobloxopen/schema-registry TAG=v7.6.1"
	@echo ""

.PHONY: submodule-init
submodule-init: ## Initialize upstream Schema Registry submodule
	@echo "→ Initializing git submodules..."
	git submodule update --init --recursive
	@echo "✓ Submodule initialized at upstream/schema-registry"

.PHONY: submodule-update
submodule-update: ## Update upstream Schema Registry to latest version
	@echo "→ Updating upstream Schema Registry submodule..."
	git submodule update --remote upstream/schema-registry
	@cd upstream/schema-registry && git describe --tags
	@echo "✓ Submodule updated"

.PHONY: build
build: ## Build container image for native platform
	@echo "→ Building $(IMAGE):$(TAG) for $(NATIVE_PLATFORM)..."
	@echo "  Base images: $(BUILDER_IMAGE) → $(RUNTIME_IMAGE)"
	@echo "  Version: $(LOCAL_VERSION) ($(REVISION))"
	docker build \
		--platform $(NATIVE_PLATFORM) \
		$(BUILD_ARGS) \
		-t $(IMAGE):$(TAG) \
		.
	@echo "✓ Build complete: $(IMAGE):$(TAG)"

.PHONY: buildx
buildx: ## Build multi-architecture image (amd64 + arm64)
	@echo "→ Building $(IMAGE):$(TAG) for $(PLATFORMS)..."
	@echo "  Base images: $(BUILDER_IMAGE) → $(RUNTIME_IMAGE)"
	@echo "  Version: $(LOCAL_VERSION) ($(REVISION))"
	docker buildx build \
		--platform $(PLATFORMS) \
		$(BUILD_ARGS) \
		-t $(IMAGE):$(TAG) \
		--load \
		.
	@echo "✓ Multi-arch build complete: $(IMAGE):$(TAG)"
	@echo ""
	@echo "To inspect manifest:"
	@echo "  docker buildx imagetools inspect $(IMAGE):$(TAG)"

.PHONY: push
push: ## Push image to registry (requires IMAGE and TAG)
	@echo "→ Pushing $(IMAGE):$(TAG) to registry..."
	docker buildx build \
		--platform $(PLATFORMS) \
		$(BUILD_ARGS) \
		-t $(IMAGE):$(TAG) \
		--push \
		.
	@echo "✓ Image pushed: $(IMAGE):$(TAG)"

.PHONY: test
test: ## Run smoke tests on built image
	@echo "→ Running smoke tests..."
	@if [ ! -f tests/smoke.sh ]; then \
		echo "⚠ tests/smoke.sh not found - skipping tests"; \
		exit 0; \
	fi
	bash tests/smoke.sh $(IMAGE):$(TAG)
	@echo "✓ Smoke tests passed"

.PHONY: clean
clean: ## Remove built images
	@echo "→ Removing local images..."
	-docker rmi $(IMAGE):$(TAG) 2>/dev/null || true
	@echo "✓ Cleanup complete"

.PHONY: info
info: ## Display build configuration
	@echo "Build Configuration:"
	@echo "  Image: $(IMAGE):$(TAG)"
	@echo "  Version: $(LOCAL_VERSION)"
	@echo "  Revision: $(REVISION)"
	@echo "  Created: $(CREATED)"
	@echo "  Native Platform: $(NATIVE_PLATFORM)"
	@echo "  Multi-Arch Platforms: $(PLATFORMS)"
	@echo ""
	@echo "Base Images:"
	@echo "  Builder: $(BUILDER_IMAGE)"
	@echo "  Runtime: $(RUNTIME_IMAGE)"
	@echo ""
	@echo "Submodule Status:"
	@git submodule status upstream/schema-registry || echo "  Not initialized"
