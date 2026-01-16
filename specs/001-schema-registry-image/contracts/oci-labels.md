# Contract: OCI Image Labels

**Type**: Metadata Contract  
**Scope**: Container Image Annotations  
**Standard**: [OCI Image Specification - Annotations](https://github.com/opencontainers/image-spec/blob/main/annotations.md)

## Overview

Defines required and optional OCI labels (metadata annotations) that MUST be present in the final container image. These labels enable provenance tracking, supply-chain verification, and operational visibility.

## Required Labels

### org.opencontainers.image.source

**Description**: URL to source code repository for image build tooling.

**Type**: String (HTTPS URL)

**Example**: `https://github.com/infobloxopen/ib-schema-registry`

**Validation**:
- MUST be valid HTTPS URL
- MUST point to this repository (build infrastructure), not upstream Schema Registry

**Purpose**: Enables tracing image back to build scripts and Dockerfile.

---

### org.opencontainers.image.version

**Description**: Semantic version of the image content (Schema Registry version + local build suffix).

**Type**: String (SemVer-compatible)

**Example**: `7.6.1+infoblox.1`

**Format**: `<UPSTREAM_VERSION>+infoblox.<BUILD_NUMBER>` or `<UPSTREAM_VERSION>-ib.<BUILD_NUMBER>`

**Validation**:
- MUST include upstream Schema Registry version number
- MUST include local build identifier
- SHOULD follow SemVer format (or SemVer build metadata)

**Purpose**: Identifies what version of Schema Registry is packaged and which local build iteration.

---

### org.opencontainers.image.revision

**Description**: Git commit SHA of this repository at build time.

**Type**: String (40-character hexadecimal)

**Example**: `a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0`

**Validation**:
- MUST be 40 characters
- MUST be hexadecimal (0-9, a-f)
- MUST correspond to actual commit in this repository

**Purpose**: Precise provenance—enables reproducing exact build by checking out this commit.

---

### org.opencontainers.image.created

**Description**: Timestamp when image was built.

**Type**: String (RFC 3339 format)

**Example**: `2026-01-15T14:32:05Z`

**Validation**:
- MUST be RFC 3339 format
- MUST include timezone (typically UTC with `Z` suffix)

**Purpose**: Auditing and lifecycle management (determine image age).

---

### org.opencontainers.image.title

**Description**: Human-readable name of image contents.

**Type**: String

**Example**: `Confluent Schema Registry`

**Validation**:
- SHOULD be concise (< 80 characters)
- SHOULD match upstream project name

**Purpose**: User-facing identification in UIs and documentation.

---

### org.opencontainers.image.description

**Description**: Summary of image purpose and contents.

**Type**: String

**Example**: `Multi-architecture OCI image for Confluent Schema Registry, built from upstream source without dockerfile-maven-plugin`

**Validation**:
- SHOULD be descriptive but concise (< 200 characters)
- SHOULD mention multi-arch and source-based nature

**Purpose**: Provides context in registry listings and documentation.

---

### org.opencontainers.image.vendor

**Description**: Organization or individual responsible for image creation.

**Type**: String

**Example**: `Infoblox` or `infobloxopen`

**Validation**:
- SHOULD match GitHub organization name or corporate identity

**Purpose**: Establishes ownership and support responsibility.

---

## Optional Labels

### org.opencontainers.image.licenses

**Description**: SPDX license identifier(s) for image contents.

**Type**: String (SPDX expression)

**Example**: `Apache-2.0 AND Confluent-Community-1.0`

**Rationale**: Dual-license reflects upstream Schema Registry licensing (Apache 2.0 + Confluent Community License for proprietary components).

**Validation**:
- SHOULD use SPDX identifiers
- SHOULD use `AND` for multiple licenses applying simultaneously

---

### org.opencontainers.image.documentation

**Description**: URL to image documentation (README or docs site).

**Type**: String (HTTPS URL)

**Example**: `https://github.com/infobloxopen/ib-schema-registry#readme`

**Purpose**: Provides users with usage instructions and examples.

---

### org.opencontainers.image.authors

**Description**: Contact information for image maintainers.

**Type**: String (email or name)

**Example**: `platform-team@infoblox.com`

**Purpose**: Support escalation path.

---

## Implementation

### Dockerfile Example

```dockerfile
ARG VERSION=dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

LABEL org.opencontainers.image.source="https://github.com/infobloxopen/ib-schema-registry" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.title="Confluent Schema Registry" \
      org.opencontainers.image.description="Multi-architecture OCI image for Confluent Schema Registry" \
      org.opencontainers.image.vendor="Infoblox" \
      org.opencontainers.image.licenses="Apache-2.0 AND Confluent-Community-1.0"
```

### Makefile Example

```makefile
VERSION := $(shell git -C upstream/schema-registry describe --tags --abbrev=0 2>/dev/null || echo "dev")
VCS_REF := $(shell git rev-parse HEAD)
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

build:
	docker build \
		--build-arg VERSION=$(VERSION)+infoblox.1 \
		--build-arg VCS_REF=$(VCS_REF) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		-t $(IMAGE):$(TAG) \
		.
```

### GitHub Actions Example

```yaml
- name: Generate metadata
  id: meta
  uses: docker/metadata-action@v5
  with:
    images: ghcr.io/${{ github.repository }}
    labels: |
      org.opencontainers.image.title=Confluent Schema Registry
      org.opencontainers.image.description=Multi-architecture OCI image for Confluent Schema Registry
      org.opencontainers.image.vendor=Infoblox
      org.opencontainers.image.licenses=Apache-2.0 AND Confluent-Community-1.0

- name: Build and push
  uses: docker/build-push-action@v5
  with:
    labels: ${{ steps.meta.outputs.labels }}
    build-args: |
      VERSION=${{ steps.version.outputs.version }}
      VCS_REF=${{ github.sha }}
      BUILD_DATE=${{ steps.meta.outputs.created }}
```

## Inspection

Users can inspect labels without running container:

```bash
# View all labels
docker inspect ghcr.io/infobloxopen/ib-schema-registry:latest | jq '.[0].Config.Labels'

# View specific label
docker inspect ghcr.io/infobloxopen/ib-schema-registry:latest \
  --format '{{ index .Config.Labels "org.opencontainers.image.version" }}'
```

## Compliance

This contract ensures compliance with:
- **SPR-011**: Image MUST include OCI labels (required labels listed above)
- **Constitution §IV**: OCI Metadata requirements for supply-chain security
- **OCI Image Specification**: Standard annotation keys recognized by tooling

## References

- [OCI Image Specification - Predefined Annotation Keys](https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys)
- [SPDX License List](https://spdx.org/licenses/)
- [RFC 3339 - Date and Time on the Internet](https://www.rfc-editor.org/rfc/rfc3339)
