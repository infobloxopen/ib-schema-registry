# Feature Specification: SLSA Provenance Attestation

**Feature Branch**: `001-slsa-provenance-attestation`  
**Created**: 2026-01-17  
**Status**: Draft  
**Input**: User description: "Add Provenance attestation (SLSA framework) to this repository's artifacts. The repository builds multi-architecture OCI container images for Confluent Schema Registry and publishes a Helm chart. Currently, the GitHub Actions workflow in .github/workflows/build-image.yml builds and pushes container images but does not generate provenance attestation."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Container Image Provenance Verification (Priority: P1)

As a security-conscious operations engineer consuming this container image, I need to verify the build provenance to ensure the image was built from trusted sources using secure build practices, so I can meet supply-chain security compliance requirements (SLSA framework).

**Why this priority**: This is the core value proposition - enabling consumers to verify image authenticity and build integrity. Without this, the feature delivers no value. This addresses the constitution's supply-chain security principle (§IV) and is the minimum viable implementation.

**Independent Test**: Can be fully tested by building an image through CI, then using standard provenance verification tools (cosign, slsa-verifier) to extract and validate the attestation without requiring Helm chart functionality.

**Acceptance Scenarios**:

1. **Given** a container image built by CI for linux/amd64, **When** I query the registry for provenance attestation, **Then** the attestation exists and contains valid SLSA build metadata
2. **Given** a container image built by CI for linux/arm64, **When** I query the registry for provenance attestation, **Then** the attestation exists and contains valid SLSA build metadata
3. **Given** a multi-arch container image manifest, **When** I verify provenance for both architectures, **Then** both architecture-specific attestations are present and independently verifiable
4. **Given** a provenance attestation, **When** I inspect its contents, **Then** it includes the source repository URL, commit SHA, build workflow reference, and timestamp
5. **Given** a provenance attestation, **When** I verify its signature, **Then** the signature is valid and traceable to the GitHub Actions OIDC identity

---

### User Story 2 - Provenance Integration in CI Pipeline (Priority: P2)

As a developer merging changes to the main branch, I need the CI pipeline to automatically generate and attach provenance attestations without breaking existing workflows, so that all published images include supply-chain metadata by default.

**Why this priority**: Enables automation at scale. Once P1 proves provenance can be generated and verified, P2 ensures it happens consistently for every build without manual intervention.

**Independent Test**: Can be tested by triggering a CI build (push to main or tag creation) and validating that the build completes successfully with attestations attached, without requiring consumer verification workflows.

**Acceptance Scenarios**:

1. **Given** a push to the main branch, **When** the CI build completes, **Then** all published container images include provenance attestations
2. **Given** a new release tag created, **When** the CI build completes, **Then** release images include provenance attestations with the tag version
3. **Given** a pull request build, **When** the build completes, **Then** provenance generation does not block the build or cause failures (may skip attestation for non-push events)
4. **Given** the existing build workflow configuration, **When** provenance generation is added, **Then** all existing build steps (QEMU setup, multi-arch build, cache usage) continue to function
5. **Given** a CI build failure, **When** reviewing logs, **Then** the failure reason is clearly indicated (build vs. attestation generation vs. attestation upload)

---

### User Story 3 - Helm Chart Provenance (Priority: P3)

As a Kubernetes cluster administrator deploying this Helm chart, I need to verify the chart's build provenance to ensure the chart package was published from trusted sources, so I can validate the entire deployment stack's supply-chain integrity.

**Why this priority**: Extends supply-chain security to the Helm chart artifact. While important for complete coverage, this is lower priority because the container image provenance (P1) addresses the primary attack vector (malicious container execution).

**Independent Test**: Can be tested by packaging and publishing a Helm chart through CI, then verifying the chart's provenance attestation using Helm or OCI registry verification tools, independently of container image provenance.

**Acceptance Scenarios**:

1. **Given** a Helm chart published to an OCI registry, **When** I query for provenance attestation, **Then** the chart includes a valid SLSA provenance attestation
2. **Given** a Helm chart provenance attestation, **When** I verify its contents, **Then** it includes the chart source repository URL, commit SHA, and chart version
3. **Given** a Helm chart with provenance, **When** I use Helm or OCI tooling to verify the attestation, **Then** verification succeeds using standard workflows

---

### Edge Cases

- **Multi-arch manifest attestation**: How are provenance attestations handled when a single manifest list references multiple architecture-specific images? Each architecture must have its own attestation attached to the architecture-specific digest.

- **PR builds without push**: When building images for pull requests (no push to registry), how is provenance handled? Provenance generation should be skipped gracefully without causing build failures.

- **Registry attestation storage limits**: What happens if the registry has size or count limits on attestations? Document any known limits for GitHub Container Registry and provide guidance.

- **Attestation verification without Sigstore**: If consumers cannot access Sigstore public-good infrastructure (air-gapped environments), how can they verify attestations? Document offline verification workflows.

- **Build matrix with provenance**: If the workflow uses a build matrix (e.g., testing different base images), does each matrix output get separate provenance? Each distinct output artifact should have its own attestation.

- **Helm chart OCI vs. HTTP hosting**: If Helm charts are served via HTTP (not OCI registry), how is provenance distributed? Provenance should be packaged alongside the chart or available at a known URL.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Container image builds MUST generate SLSA provenance attestations that are attached to the published OCI images
- **FR-002**: Provenance attestations MUST work with multi-architecture builds (linux/amd64 and linux/arm64) with separate attestations for each architecture
- **FR-003**: Provenance attestations MUST include the source repository URL, commit SHA, GitHub Actions workflow reference, and build timestamp
- **FR-004**: Provenance attestations MUST be cryptographically signed using the GitHub Actions OIDC identity
- **FR-005**: Provenance generation MUST NOT break existing CI workflows including build caching, multi-arch builds, QEMU setup, or image testing
- **FR-006**: Provenance attestations MUST be queryable and verifiable using standard OCI registry tooling
- **FR-007**: Build failures MUST clearly distinguish between build errors, provenance generation errors, and attestation upload errors
- **FR-008**: Helm chart artifacts SHOULD include SLSA provenance attestations when published to OCI registries
- **FR-009**: Documentation MUST include instructions for verifying provenance attestations using common verification tools
- **FR-010**: PR builds (no registry push) MUST handle provenance generation gracefully without causing failures

### Security & Portability Requirements

- **SPR-001**: Provenance generation MUST maintain support for multi-architecture builds (linux/amd64 and linux/arm64) as required by constitution §II
- **SPR-002**: Provenance attestations MUST be compatible with GitHub Container Registry (ghcr.io) attestation storage mechanisms
- **SPR-003**: Attestation signing MUST use GitHub's built-in OIDC token provider without requiring additional secret management
- **SPR-004**: The solution MUST use either Docker buildx built-in provenance features or GitHub-native SLSA generators to avoid third-party dependencies
- **SPR-005**: Provenance generation MUST NOT require modifications to the Dockerfile or runtime image structure
- **SPR-006**: The implementation MUST align with constitution §IV supply-chain security requirements (non-root runtime, pinned dependencies, no secrets in layers remain unchanged)
- **SPR-007**: Documentation MUST include guidance for offline/air-gapped attestation verification scenarios

### Assumptions

- **ASM-001**: GitHub Container Registry supports OCI image attestation storage (via OCI reference types or attestation manifest extensions)
- **ASM-002**: Consumers have access to standard verification tools (e.g., cosign, slsa-verifier, or docker buildx imagetools inspect)
- **ASM-003**: The repository will continue using GitHub Actions as the primary CI platform
- **ASM-004**: SLSA Level 1 (provenance exists and includes basic build info) is the initial target; higher levels (build isolation, reproducibility) are future enhancements
- **ASM-005**: The existing docker/build-push-action@v5 supports provenance generation via buildx/buildkit features
- **ASM-006**: Helm chart provenance (P3) will follow similar patterns to OCI image attestation if Helm charts are published to OCI-compatible registries

### Key Entities

- **Provenance Attestation**: A cryptographically signed document containing metadata about how an artifact was built, including source location, build environment, build steps, and dependencies. Conforms to SLSA provenance schema.

- **Multi-arch Manifest**: An OCI image index (manifest list) that references architecture-specific image manifests. Each architecture-specific image should have its own attestation.

- **Attestation Signature**: A cryptographic signature over the provenance attestation, created using the GitHub Actions OIDC identity and verifiable using the Sigstore public-good infrastructure.

- **Verification Tool**: Software used by consumers to extract, validate, and inspect provenance attestations (e.g., cosign for signature verification, slsa-verifier for SLSA-specific validation, docker buildx for OCI inspection).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every container image published to the registry includes a verifiable SLSA provenance attestation (100% coverage for builds from main branch and release tags)

- **SC-002**: Provenance attestations for both linux/amd64 and linux/arm64 architectures can be independently retrieved and verified within 30 seconds using standard verification tools

- **SC-003**: CI build times increase by no more than 10% after adding provenance generation (measured against pre-implementation baseline on identical hardware)

- **SC-004**: All existing CI workflows continue to pass without modification beyond provenance enablement

- **SC-005**: Documentation enables a new consumer to verify image provenance in under 5 minutes following the provided instructions (validated through user testing)

- **SC-006**: Zero build failures attributed to provenance generation or attestation upload in the first month after deployment (excluding infrastructure outages)

- **SC-007**: Helm chart artifacts include provenance attestations (if P3 is implemented; otherwise this criterion is deferred)

### Validation Methods

- **Automated CI Tests**: Add a validation step to the CI pipeline that verifies the presence and validity of provenance attestations immediately after image publication

- **Manual Verification**: Document step-by-step verification procedures using industry-standard verification tools for both maintainers and consumers

- **Performance Benchmarking**: Compare CI build durations before and after implementation using CI platform metrics over a minimum of 10 builds

- **User Acceptance Testing**: Have at least two external consumers (security-focused users) validate they can successfully verify attestations following the documentation
