# Feature Specification: Fix SBOM Generation for Multi-Architecture Images

**Feature Branch**: `004-sbom-generation-fix`  
**Created**: 2026-01-17  
**Status**: Draft  
**Input**: User description: "Fix SBOM generation failure when digest already exists. SBOM generation should succeed and verify identical SBOMs when rebuilding same image."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Generate SBOM for New Image (Priority: P1)

A release engineer runs the SBOM generation process for a newly built multi-architecture container image. They execute the generation script which introspects the image and produces a Software Bill of Materials artifact for supply chain transparency and audit purposes.

**Why this priority**: Core MVP functionality. The ability to generate an initial SBOM for any new image is the foundation of the entire feature. Without this, SBOM generation cannot function.

**Independent Test**: Run SBOM generation script against a freshly built image that has no existing SBOM artifact, verify successful completion and valid SBOM file output.

**Acceptance Scenarios**:

1. **Given** a newly built container image with a unique digest, **When** the SBOM generation script runs, **Then** an SBOM file is created successfully
2. **Given** SBOM generation completes, **When** inspecting the output artifact, **Then** it contains required SPDX or CycloneDX formatted supply chain data
3. **Given** multi-architecture images (linux/amd64 and linux/arm64), **When** running SBOM generation, **Then** both architectures are processed and SBOMs generated

---

### User Story 2 - Idempotent SBOM Generation (Priority: P1)

A release engineer rebuilds the exact same image digest from the same source code and attempts to run SBOM generation again. The system detects that an SBOM for this digest already exists, verifies it is identical to what would be newly generated, and succeeds without overwriting or failing.

**Why this priority**: Critical for production reliability. This directly addresses the reported failure ("cannot overwrite digest"). Users must be able to re-run SBOM generation for the same image digest without encountering conflicts or errors.

**Independent Test**: Generate SBOM for an image, rebuild the exact same image (same digest), run SBOM generation again, verify success and that existing SBOM is either reused or verified as identical.

**Acceptance Scenarios**:

1. **Given** an existing SBOM for image digest X, **When** SBOM generation runs against the same digest X again, **Then** the operation succeeds without error
2. **Given** an existing SBOM, **When** attempting to regenerate for the same digest, **Then** the system verifies the new SBOM matches the existing one (hash comparison)
3. **Given** identical verification, **When** the process completes, **Then** the user receives confirmation that SBOM exists and is valid (not an error about overwrite conflicts)

---

### User Story 3 - Update SBOM When Image Changes (Priority: P2)

A developer rebuilds the image with dependency or code changes, producing a new digest. They run SBOM generation which recognizes the new digest and generates a fresh SBOM to reflect the updated supply chain.

**Why this priority**: Important for ongoing maintenance and security updates, but secondary to handling the same digest scenario. Must work correctly but can be implemented after idempotency is confirmed.

**Independent Test**: Modify Dockerfile or dependencies, rebuild image (creating new digest), run SBOM generation, verify new SBOM is created and reflects updated dependency set.

**Acceptance Scenarios**:

1. **Given** an SBOM exists for digest A, **When** the image is rebuilt with changes creating digest B, **Then** SBOM generation for digest B creates a new SBOM artifact
2. **Given** different digests, **When** both SBOMs are compared, **Then** they reflect the actual differences in image contents/dependencies
3. **Given** updated image, **When** SBOM generation completes, **Then** metadata correctly reflects the new image digest and timestamp

---

### User Story 4 - SBOM Generation in CI/CD Pipeline (Priority: P2)

A DevOps engineer has integrated SBOM generation into their GitHub Actions workflow. The workflow builds multi-architecture images and automatically generates SBOMs for each build, handling both new images and rebuilds of existing digests gracefully.

**Why this priority**: Automation context is important for real-world usage, but the core idempotency fix (P1) must work first. This validates the fix works in the CI/CD environment.

**Independent Test**: Execute CI workflow, verify SBOM generation completes for all images in pipeline, check that rebuild scenarios don't cause workflow failures.

**Acceptance Scenarios**:

1. **Given** a GitHub Actions workflow that builds and generates SBOMs, **When** code is pushed to main, **Then** workflow completes successfully
2. **Given** a second push with the same source (creating same digests), **When** the workflow runs again, **Then** SBOM generation succeeds without failures
3. **Given** successful SBOM generation in CI, **When** artifacts are logged, **Then** SBOMs are available as build outputs for compliance and audit

---

### Edge Cases

- What happens if SBOM generation is interrupted and partially completed for a digest?
- How does the system handle concurrent SBOM generation requests for the same image digest?
- What occurs if the SBOM storage location (disk/cache) is corrupted or inaccessible?
- How should the system behave if SBOM format differs between old and newly generated versions (schema version changes)?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support SBOM generation for container images via the existing `generate-sbom.sh` script
- **FR-002**: System MUST detect when an SBOM already exists for a given image digest
- **FR-003**: System MUST compare newly generated SBOM data with existing SBOM to verify content identity
- **FR-004**: System MUST succeed (not fail) when an SBOM is regenerated for the same digest, provided content is identical
- **FR-005**: System MUST replace SBOM if regenerated content differs from existing SBOM (e.g., updated dependencies)
- **FR-006**: System MUST handle multi-architecture image digests independently (each arch can have its own SBOM)
- **FR-007**: System MUST store SBOM artifacts in a persistent, organized location indexed by image digest
- **FR-008**: System MUST provide clear logging/output indicating whether SBOM was newly generated, verified identical, or updated
- **FR-009**: System MUST handle concurrent or rapid sequential invocations without data corruption or conflicts
- **FR-010**: System MUST validate SBOM format and completeness before accepting as valid output

### Security & Portability Requirements

- **SPR-001**: SBOM MUST be generated for both linux/amd64 and linux/arm64 architectures in multi-arch builds
- **SPR-002**: SBOM generation MUST NOT require modification of image contents or files
- **SPR-003**: SBOM storage and artifact locations MUST be filesystem-agnostic (work on Linux, macOS, GitHub Actions runners)
- **SPR-004**: SBOM MUST be captured using standard tooling compatible with the runtime (syft, trivy, or similar) that works with OCI image digests
- **SPR-005**: Generated SBOM MUST be reproducible - same input image digest produces identical SBOM output

### Key Entities

- **Image Digest**: Unique identifier (SHA256 hash) for a container image, including per-architecture digests in multi-arch scenarios
- **SBOM**: Software Bill of Materials in SPDX or CycloneDX format containing list of software components, versions, licenses
- **SBOM Cache/Store**: Persistent storage location mapping image digests to corresponding SBOM artifacts
- **Generation Script**: `scripts/sbom/generate-sbom.sh` which orchestrates SBOM tooling and output

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: SBOM generation succeeds for newly built images (100% success rate on first generation)
- **SC-002**: SBOM generation succeeds when re-run against same image digest without errors or conflicts (0% failure rate on idempotent runs)
- **SC-003**: Existing SBOM verification completes in under 5 seconds (digest lookup + hash comparison overhead minimal)
- **SC-004**: Multi-architecture builds generate SBOM for both linux/amd64 and linux/arm64 independently without conflicts
- **SC-005**: SBOM generation workflow in CI/CD completes successfully on 100% of build runs (no transient failures due to digest conflicts)
- **SC-006**: Users can re-run SBOM generation multiple times for same image without manual workarounds or cleanup steps
- **SC-007**: Generated SBOMs are reproducible - running generation twice on same image digest produces byte-identical output

### Assumptions

- SBOM generation tool (syft or trivy) is already configured and functional
- OCI image digests are available and reliable identifiers for image identity
- Filesystem storage is sufficient for SBOM artifacts (typical SBOMs are < 1MB)
- Multi-architecture builds produce distinct digests per architecture
