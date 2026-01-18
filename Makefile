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

# Version file for caching computed version (avoids recomputation)
VERSION_FILE := .version.mk

# Include cached version if it exists
-include $(VERSION_FILE)

# Version metadata (use cached values from .version.mk, fallback to defaults)
VERSION ?= dev
UPSTREAM_VERSION ?= dev
SHA ?= $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
REVISION := $(SHA)
CREATED := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# Docker build arguments
BUILD_ARGS := --build-arg BUILDER_IMAGE=$(BUILDER_IMAGE) \
              --build-arg RUNTIME_IMAGE=$(RUNTIME_IMAGE) \
              --build-arg VERSION=$(VERSION) \
              --build-arg UPSTREAM_VERSION=$(UPSTREAM_VERSION) \
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
	@grep -E '^[a-zA-Z_0-9-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration:"
	@echo "  IMAGE=$(IMAGE)"
	@echo "  TAG=$(TAG)"
	@echo "  VERSION=$(VERSION)"
	@echo "  UPSTREAM_VERSION=$(UPSTREAM_VERSION)"
	@echo "  NATIVE_PLATFORM=$(NATIVE_PLATFORM)"
	@echo ""
	@echo "Base Images:"
	@echo "  BUILDER_IMAGE=$(BUILDER_IMAGE)"
	@echo "  RUNTIME_IMAGE=$(RUNTIME_IMAGE)"
	@echo ""
	@echo "Examples:"
	@echo "  make version                        # Show computed version"
	@echo "  make build                          # Build for native platform"
	@echo "  make buildx                         # Build for all platforms"
	@echo "  make build RUNTIME_IMAGE=eclipse-temurin:17-jre  # Temurin alternative"
	@echo "  make push IMAGE=ghcr.io/infobloxopen/schema-registry TAG=v8.1.1"
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
	@echo "→ Recomputing version after submodule update..."
	@$(MAKE) version-file

.PHONY: version-file
version-file: ## Compute version and cache to .version.mk file
	@echo "→ Computing version..."
	@./scripts/version.sh --format=make --quiet > $(VERSION_FILE)
	@echo "✓ Version cached to $(VERSION_FILE)"

.PHONY: version
version: version-file ## Display computed version information
	@echo "═══════════════════════════════════════════════════════"
	@echo "Version Information"
	@echo "═══════════════════════════════════════════════════════"
	@cat $(VERSION_FILE) | sed 's/^/  /'
	@echo ""
	@echo "Full version string:"
	@echo "  $(VERSION)"
	@echo ""
	@echo "Format: <upstream>-ib.<suffix>.<sha>[.dirty]"
	@echo "  upstream: Upstream Confluent Schema Registry version"
	@echo "  suffix:   Release number OR branch name (sanitized)"
	@echo "  sha:      Short Git commit SHA (7 characters)"
	@echo "  .dirty:   Present if uncommitted changes exist"

.PHONY: version-validate
version-validate: version-file ## Validate computed version format
	@echo "→ Validating computed version..."
	@./scripts/validate-version.sh "$(VERSION)"

.PHONY: build
build: version-file ## Build container image for native platform
	@echo "→ Building $(IMAGE):$(TAG) for $(NATIVE_PLATFORM)..."
	@echo "  Base images: $(BUILDER_IMAGE) → $(RUNTIME_IMAGE)"
	@echo "  Version: $(VERSION) (upstream: $(UPSTREAM_VERSION), sha: $(SHA))"
	docker build \
		--platform $(NATIVE_PLATFORM) \
		$(BUILD_ARGS) \
		-t $(IMAGE):$(TAG) \
		.
	@echo "✓ Build complete: $(IMAGE):$(TAG)"

.PHONY: buildx
buildx: version-file ## Build multi-architecture image (amd64 + arm64)
	@echo "→ Building $(IMAGE):$(TAG) for $(PLATFORMS)..."
	@echo "  Base images: $(BUILDER_IMAGE) → $(RUNTIME_IMAGE)"
	@echo "  Version: $(VERSION) (upstream: $(UPSTREAM_VERSION), sha: $(SHA))"
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
push: version-file ## Push image to registry (requires IMAGE and TAG)
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
	@echo "  Version: $(VERSION)"
	@echo "  Upstream Version: $(UPSTREAM_VERSION)"
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

# -----------------------------------------------------------------------------
# Helm Chart Targets (Feature 003)
# -----------------------------------------------------------------------------

CHART_DIR := helm/ib-schema-registry
CHART_NAME := ib-schema-registry
CHART_VERSION ?= 0.1.0
REGISTRY ?= ghcr.io/infobloxopen

.PHONY: helm-lint
helm-lint: ## Lint Helm chart
	@echo "→ Linting Helm chart..."
	helm lint $(CHART_DIR)
	@echo "✓ Helm lint passed"

.PHONY: helm-package
helm-package: ## Package Helm chart as .tgz
	@echo "→ Packaging Helm chart..."
	helm package $(CHART_DIR) --version $(CHART_VERSION)
	@echo "✓ Chart packaged: $(CHART_NAME)-$(CHART_VERSION).tgz"

.PHONY: helm-push
helm-push: helm-package ## Push Helm chart to OCI registry
	@echo "→ Pushing Helm chart to $(REGISTRY)..."
	helm push $(CHART_NAME)-$(CHART_VERSION).tgz oci://$(REGISTRY)
	@echo "✓ Chart pushed: oci://$(REGISTRY)/$(CHART_NAME):$(CHART_VERSION)"

.PHONY: helm-test-e2e
helm-test-e2e: ## Run end-to-end tests with k3d
	@echo "→ Running Helm chart E2E tests..."
	@if [ ! -f tests/e2e/test-helm-chart.sh ]; then \
		echo "⚠ tests/e2e/test-helm-chart.sh not found - skipping tests"; \
		exit 0; \
	fi
	bash tests/e2e/test-helm-chart.sh
	@echo "✓ E2E tests passed"

# -----------------------------------------------------------------------------
# SBOM Generation Targets (Feature 004)
# -----------------------------------------------------------------------------

SBOM_DIR := build/sbom
SBOM_TAG ?= $(TAG)

.PHONY: sbom-install-tools
sbom-install-tools: ## Install SBOM generation tools (Syft, Grype)
	@echo "→ Installing SBOM tools..."
	@echo "  Installing Syft..."
	@curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
	@echo "  Installing Grype..."
	@curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
	@echo "✓ SBOM tools installed"
	@echo ""
	@syft version
	@grype version

.PHONY: sbom
sbom: ## Generate SBOM for built image (both CycloneDX and SPDX) - Idempotent operation
	@echo "→ Generating SBOM for $(IMAGE):$(SBOM_TAG)..."
	@mkdir -p $(SBOM_DIR)
	@echo "  Platform: $(NATIVE_PLATFORM)"
	@echo ""
	@echo "→ Generating CycloneDX SBOM..."
	@bash scripts/sbom/generate-sbom.sh \
		$(IMAGE):$(SBOM_TAG) \
		cyclonedx-json \
		$(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).cyclonedx.json \
		$(NATIVE_PLATFORM)
	@echo ""
	@echo "→ Generating SPDX SBOM..."
	@bash scripts/sbom/generate-sbom.sh \
		$(IMAGE):$(SBOM_TAG) \
		spdx-json \
		$(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).spdx.json \
		$(NATIVE_PLATFORM)
	@echo ""
	@echo "✓ SBOM generation complete"
	@echo ""
	@echo "Generated files:"
	@ls -lh $(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).*
	@echo ""
	@echo "Metadata:"
	@for metadata in $(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).*.metadata.json; do \
		if [ -f "$$metadata" ]; then \
			echo "  $$metadata:"; \
			command -v jq >/dev/null && jq -r '.operation // "unknown"' "$$metadata" | sed 's/^/    Operation: /'; \
		fi; \
	done
	@echo ""
	@echo "Next steps:"
	@echo "  make sbom-validate SBOM_TAG=$(SBOM_TAG)  # Validate and scan for vulnerabilities"
	@echo "  make sbom-idempotent-test SBOM_TAG=$(SBOM_TAG)  # Test idempotency (run twice)"

.PHONY: sbom-multi
sbom-multi: ## Generate SBOMs for all platforms (amd64 + arm64)
	@echo "→ Generating multi-architecture SBOMs for $(IMAGE):$(SBOM_TAG)..."
	@mkdir -p $(SBOM_DIR)
	@echo ""
	@echo "→ Generating SBOMs for linux/amd64..."
	@bash scripts/sbom/generate-sbom.sh \
		$(IMAGE):$(SBOM_TAG) \
		cyclonedx-json \
		$(SBOM_DIR)/$(SBOM_TAG)-amd64.cyclonedx.json \
		linux/amd64
	@bash scripts/sbom/generate-sbom.sh \
		$(IMAGE):$(SBOM_TAG) \
		spdx-json \
		$(SBOM_DIR)/$(SBOM_TAG)-amd64.spdx.json \
		linux/amd64
	@echo ""
	@echo "→ Generating SBOMs for linux/arm64..."
	@bash scripts/sbom/generate-sbom.sh \
		$(IMAGE):$(SBOM_TAG) \
		cyclonedx-json \
		$(SBOM_DIR)/$(SBOM_TAG)-arm64.cyclonedx.json \
		linux/arm64
	@bash scripts/sbom/generate-sbom.sh \
		$(IMAGE):$(SBOM_TAG) \
		spdx-json \
		$(SBOM_DIR)/$(SBOM_TAG)-arm64.spdx.json \
		linux/arm64
	@echo ""
	@echo "✓ Multi-architecture SBOM generation complete"
	@echo ""
	@echo "Generated files:"
	@ls -lh $(SBOM_DIR)/$(SBOM_TAG)-*.{cyclonedx,spdx}.json 2>/dev/null || true
	@echo ""
	@echo "Next steps:"
	@echo "  make sbom-validate SBOM_TAG=$(SBOM_TAG)  # Validate all SBOMs"

.PHONY: sbom-validate
sbom-validate: ## Validate SBOMs and scan for vulnerabilities
	@echo "→ Validating SBOMs for $(SBOM_TAG)..."
	@echo ""
	@for sbom_file in $(SBOM_DIR)/$(SBOM_TAG)-*.json; do \
		if [ -f "$$sbom_file" ]; then \
			echo "═══════════════════════════════════════════════════════"; \
			bash scripts/sbom/validate-sbom.sh "$$sbom_file"; \
			echo ""; \
		fi; \
	done
	@echo "✓ All SBOM validations complete"

.PHONY: sbom-idempotent-test
sbom-idempotent-test: ## Test idempotency: Run SBOM generation twice, verify both succeed with same digest
	@echo "═══════════════════════════════════════════════════════"
	@echo "Idempotency Test: Generate SBOM twice for same image"
	@echo "═══════════════════════════════════════════════════════"
	@echo ""
	@echo "Test Image: $(IMAGE):$(SBOM_TAG)"
	@echo "Platform: $(NATIVE_PLATFORM)"
	@echo ""
	@mkdir -p $(SBOM_DIR)
	@echo "───────────────────────────────────────────────────────"
	@echo "RUN 1: Initial SBOM generation"
	@echo "───────────────────────────────────────────────────────"
	@bash scripts/sbom/generate-sbom.sh \
		$(IMAGE):$(SBOM_TAG) \
		cyclonedx-json \
		$(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).cyclonedx.json \
		$(NATIVE_PLATFORM)
	@echo ""
	@if [ -f "$(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).cyclonedx.json.metadata.json" ]; then \
		echo "Run 1 Metadata:"; \
		jq -r '.operation // "unknown"' "$(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).cyclonedx.json.metadata.json" | sed 's/^/  Operation: /'; \
		echo ""; \
	fi
	@echo "───────────────────────────────────────────────────────"
	@echo "RUN 2: Re-run SBOM generation (should be idempotent)"
	@echo "───────────────────────────────────────────────────────"
	@bash scripts/sbom/generate-sbom.sh \
		$(IMAGE):$(SBOM_TAG) \
		cyclonedx-json \
		$(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).cyclonedx.json \
		$(NATIVE_PLATFORM)
	@echo ""
	@if [ -f "$(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).cyclonedx.json.metadata.json" ]; then \
		echo "Run 2 Metadata:"; \
		jq -r '.operation // "unknown"' "$(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).cyclonedx.json.metadata.json" | sed 's/^/  Operation: /'; \
		echo ""; \
	fi
	@echo "───────────────────────────────────────────────────────"
	@echo "Idempotency Test Results:"
	@echo "───────────────────────────────────────────────────────"
	@if [ -f "$(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).cyclonedx.json.metadata.json" ]; then \
		OPERATION=$$(jq -r '.operation // "unknown"' "$(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).cyclonedx.json.metadata.json"); \
		if [ "$$OPERATION" = "VERIFIED_IDENTICAL" ]; then \
			echo "✓ PASS: Second run reported VERIFIED_IDENTICAL"; \
			echo "✓ PASS: SBOM file was not overwritten"; \
			echo "✓ PASS: Idempotency working correctly"; \
		else \
			echo "✗ FAIL: Second run reported $$OPERATION (expected VERIFIED_IDENTICAL)"; \
			exit 1; \
		fi; \
	else \
		echo "✗ FAIL: Metadata file not found"; \
		exit 1; \
	fi
	@echo ""
	@echo "Generated SBOM files:"
	@ls -lh $(SBOM_DIR)/$(SBOM_TAG)-$(NATIVE_ARCH).cyclonedx.json* 2>/dev/null || true

.PHONY: sbom-clean
sbom-clean: ## Remove generated SBOM files
	@echo "→ Cleaning SBOM directory..."
	@rm -rf $(SBOM_DIR)
	@echo "✓ SBOM directory cleaned"

