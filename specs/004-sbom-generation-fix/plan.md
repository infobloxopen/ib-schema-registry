# Implementation Plan: Fix SBOM Generation for Multi-Architecture Images

**Branch**: `004-sbom-generation-fix` | **Date**: 2026-01-17 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-sbom-generation-fix/spec.md`

## Summary

**Primary Requirement**: Fix the "cannot overwrite digest" error in SBOM generation when the same image digest is built multiple times. The system must detect existing SBOMs, verify content identity through hash comparison, and succeed without conflict when regenerating identical SBOMs.

**Technical Approach**: 
1. Enhance `scripts/sbom/generate-sbom.sh` to implement digest-based caching with idempotent operation
2. Add SBOM existence detection and hash comparison before output
3. Implement clear logging to indicate operation type (new generation, verification, update)
4. Store SBOM artifacts indexed by image digest in `build/sbom/` directory
5. Update Makefile targets to support the new idempotent behavior
6. Extend CI/CD workflow to validate idempotent SBOM generation succeeds

## Technical Context

**Language/Version**: Bash (shell script), compatible with Linux/macOS/GitHub Actions  
**Primary Dependencies**: Syft (v1.0.0+) for SBOM generation, jq for JSON processing, coreutils (sha256sum, stat)  
**Storage**: Filesystem (`build/sbom/`) - no database required  
**Testing**: Shell test scripts (bats framework optional), manual smoke tests via Makefile targets  
**Target Platform**: Linux servers (CI/CD) and macOS (local development), both amd64 and arm64 architectures
**Project Type**: Build tooling / Build automation scripts  
**Performance Goals**: Digest detection and hash comparison must complete in <5 seconds per invocation
**Constraints**: Must work without external dependencies beyond Syft; must not require Docker socket modifications or privileged mode
**Scale/Scope**: Two architecture variants (amd64, arm64); single image per invocation

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Multi-arch portability**: SBOM generation works identically on macOS ARM and Linux x86 via Syft (platform-agnostic tool); Makefile targets unified without platform-specific scripts
- [x] **Base image pluggability**: SBOM generation is decoupled from container build process; independent of which runtime/builder base images are selected
- [x] **Distroless compatibility**: SBOM generation is introspection-only (non-destructive); does not require shell or file modification in runtime container
- [x] **Supply-chain security**: 
  - [x] SBOM artifacts stored in filesystem without secrets
  - [x] No untrusted binary downloads (uses Syft stable releases)
  - [x] Output indexed by image digest (SHA256 hash) enabling reproducibility verification
  - [x] OCI labels in image capture source/version metadata for audit trail
- [x] **Licensing compliance**: SBOM captures upstream component licenses; no upstream code copied (read-only from container image)
- [x] **Repository ergonomics**: New Makefile targets (`make sbom`, `make sbom-multi`) documented with clear help text and sequential output
- [x] **Testing validation**: SBOM generation tested in both single-arch (`make sbom`) and multi-arch (`make sbom-multi`) scenarios; smoke tests validate output file existence and format

**Violations**: None identified. All core principles are satisfied by design.

## Project Structure

### Documentation (this feature)

```text
specs/004-sbom-generation-fix/
├── spec.md                      # Feature specification (requirements, user stories)
├── plan.md                      # This file (technical architecture, Phase 0-1 plan)
├── research.md                  # Phase 0 output (resolved unknowns, design decisions)
├── data-model.md                # Phase 1 output (SBOM data model, file structure)
├── quickstart.md                # Phase 1 output (walkthrough of new SBOM feature)
└── contracts/                   # Phase 1 output
    └── sbom-cache-interface.md  # Storage contract for SBOM artifacts
```

### Source Code (repository root)

```text
scripts/sbom/
├── generate-sbom.sh             # ENHANCED: Add idempotent digest-based caching
├── validate-sbom.sh             # Unchanged: Validates SBOM format/vulnerabilities
└── README.md                    # UPDATED: Document digest caching behavior

build/sbom/                       # NEW: SBOM artifact storage
├── [image-tag]-amd64.cyclonedx.json
├── [image-tag]-amd64.metadata.json
├── [image-tag]-arm64.cyclonedx.json
└── [image-tag]-arm64.metadata.json

Makefile                          # UPDATED: Add sbom-idempotent target, update help text
```

**Structure Decision**: Single bash script approach (no new modules). SBOM cache implemented as filesystem index by digest. Existing Makefile infrastructure extended with new targets.

## Phase 0: Research & Design

**Completed**: ✅

Generated artifact: [research.md](research.md)

**Deliverables**:
- ✅ Resolved unknowns about Syft determinism and digest uniqueness
- ✅ Design decision: Hash-based idempotency verification
- ✅ Concurrency handling strategy: Atomic file operations + retry logic
- ✅ Storage structure: Filesystem index with metadata.json per SBOM
- ✅ Testing approach: Makefile smoke tests + CI/CD validation

**Key Findings**:
- Syft is deterministic: same image digest produces bit-identical SBOM
- "cannot overwrite digest" error is from CI wrapper, not Syft itself
- SHA256 content hash sufficient for idempotency verification
- Atomic rename provides safe concurrent access
- No new test infrastructure needed

---

## Phase 1: Design & Contracts

**Completed**: ✅

Generated artifacts: [data-model.md](data-model.md), [contracts/sbom-cache-interface.md](contracts/sbom-cache-interface.md), [quickstart.md](quickstart.md)

**Deliverables**:

### Data Model
- ✅ SBOM file entity: format, content, digest tracking
- ✅ Metadata file entity: digest, hash, operation status, timestamps
- ✅ Image digest: unique per architecture, used as primary index
- ✅ Operation types: GENERATED, VERIFIED_IDENTICAL, UPDATED
- ✅ File structure: `build/sbom/[tag]-[arch].[format].json`
- ✅ Validation rules: SBOM format, metadata schema, hash verification

### Storage Contract (Interface)
- ✅ `detect_existing_sbom()`: Check if prior version exists
- ✅ `compute_sbom_hash()`: Calculate SHA256 for comparison
- ✅ `verify_sbom_identical()`: Verify content equivalence
- ✅ `write_sbom_metadata()`: Persist metadata with audit trail
- ✅ `should_overwrite_sbom()`: Decision logic for file updates
- ✅ Concurrency safety: Atomic operations, timeout/retry behavior
- ✅ Filesystem contract: Directory structure, naming convention, permissions
- ✅ Status reporting: Operation codes, output format, metadata fields

### Quickstart Guide
- ✅ Generate SBOM for native platform: `make sbom`
- ✅ Idempotent regeneration: Same command, same digest = VERIFIED_IDENTICAL
- ✅ Update SBOM when image changes: New digest = UPDATED operation
- ✅ Multi-architecture: `make sbom-multi` for amd64 + arm64
- ✅ CI/CD workflow example: GitHub Actions integration
- ✅ Validation and auditing: Inspect metadata, view operation status
- ✅ Troubleshooting guide: Common errors and solutions

---

## Phase 2 (Planning): Implementation Tasks

**Not yet executed** (next phase: `/speckit.tasks`)

**Expected deliverables** (to be generated by `/speckit.tasks`):
- `tasks.md`: Concrete implementation tasks with acceptance criteria
- CI/CD workflow: GitHub Actions steps for building and SBOM generation
- Shell script enhancements: Idempotency functions in generate-sbom.sh
- Makefile targets: New `sbom-idempotent`, smoke test targets
- Documentation: README updates, inline comments in scripts

---

## Re-evaluation: Constitution Check (Post-Design)

*Gate: All design decisions above must satisfy constitution principles*

- [x] **Multi-arch portability**: SBOM generation tool (Syft) platform-agnostic; Makefile targets work on macOS ARM and Linux x86
- [x] **Base image pluggability**: SBOM is decoupled from build; independent of runtime/builder base image choices
- [x] **Distroless compatibility**: SBOM is read-only introspection; no shell modifications to runtime container
- [x] **Supply-chain security**: 
  - [x] Artifact storage filesystem-based, no external secrets
  - [x] Uses stable Syft releases (no untrusted downloads)
  - [x] Digest-based indexing enables reproducibility verification
  - [x] Metadata contains source digest + hash for audit trail
- [x] **Licensing**: SBOM captures upstream component licenses without copying code
- [x] **Repository ergonomics**: Makefile targets clear and documented
- [x] **Testing**: Multi-arch validation via smoke tests and CI/CD

**Result**: ✅ **All principles satisfied. No violations identified.**

---

## Summary of Technical Decisions

| Aspect | Chosen Approach | Rationale |
|--------|-----------------|-----------|
| **Hash Algorithm** | SHA256 of SBOM file | Standard, fast, reliable for idempotency verification |
| **Storage Index** | Filesystem metadata.json | Decouples human-readable filenames from unique digest tracking |
| **Concurrency** | Atomic file ops + retry | Simple, safe, acceptable for build tooling |
| **Implementation** | Enhance generate-sbom.sh via lib | Minimal changes, backward compatible |
| **Status Communication** | Operation enum in metadata | Clear audit trail, CI-parseable |
| **Testing** | Makefile smoke tests | Lightweight, no new infrastructure |
| **Multi-arch** | Independent SBOMs per architecture | Prevents digest conflicts between platforms |

---

## Next Steps

1. **Execute Phase 2** (`/speckit.tasks`): Generate concrete implementation tasks
2. **Implement enhancements**: Modify `scripts/sbom/generate-sbom.sh`, Makefile, CI workflow
3. **Validate on branch**: Test new idempotent behavior locally and in CI
4. **Merge to main**: Complete feature implementation per tasks
