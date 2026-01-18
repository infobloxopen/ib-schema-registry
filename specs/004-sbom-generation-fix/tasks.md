# Implementation Tasks: Fix SBOM Generation for Multi-Architecture Images

**Feature**: SBOM Generation Fix (004-sbom-generation-fix)  
**Branch**: `004-sbom-generation-fix`  
**Status**: Ready for implementation  
**Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md) | **Data Model**: [data-model.md](data-model.md)

---

## Overview & Dependency Graph

### User Stories (Dependency Order)

```
Phase 1 Setup & Foundations (blocking all stories)
    ↓
Phase 3: US1 - Generate SBOM for New Image (P1) [MVP Foundation]
    ↓
Phase 4: US2 - Idempotent SBOM Generation (P1) [Critical for issue #14 fix]
    ↓
Phase 5: US3 - Update SBOM When Image Changes (P2) [Optional, follows US2]
Phase 6: US4 - SBOM in CI/CD Pipeline (P2) [Parallel with US3]
    ↓
Phase 7: Polish & Cross-Cutting Concerns

```

### Parallel Execution Opportunities

After completing Setup & Foundational (Phase 1-2):
- **US3 and US4 can be implemented in parallel** (independent Makefile/workflow targets)
- **Per-architecture SBOM generation** (amd64 and arm64) can run in parallel (already supported by Syft --platform)

### Independent Test Criteria per User Story

| Story | MVP Test | Full Test |
|-------|----------|-----------|
| **US1** | `make sbom TAG=test` creates .json files | CycloneDX & SPDX formats both valid |
| **US2** | Run `make sbom TAG=test` twice, both succeed (0 exit code) | Hash matches, operation=VERIFIED_IDENTICAL |
| **US3** | Modify source, rebuild image, `make sbom`, new SBOM differs | Content hashes don't match, operation=UPDATED |
| **US4** | Push to branch, GitHub Actions runs sbom targets | CI doesn't fail on rebuild (idempotent) |

---

## Phase 1: Setup & Project Initialization

> **Goal**: Establish directory structure and foundation for SBOM feature  
> **Independent Test**: Directory structure in place, no build errors

- [x] T001 Create SBOM artifact directory structure at build/sbom/
- [x] T002 Create scripts/sbom/lib-idempotent.sh shell library for caching functions
- [x] T003 [P] Add .gitignore rules for build/sbom/ directory (exclude artifacts, include .gitkeep)

---

## Phase 2: Foundational Components (Blocking Prerequisites)

> **Goal**: Implement core utility functions that all user stories depend on  
> **Independent Test**: Functions callable, return correct exit codes, proper error handling

- [x] T004 Implement `detect_existing_sbom()` function in scripts/sbom/lib-idempotent.sh
- [x] T005 Implement `compute_sbom_hash()` function using sha256sum in scripts/sbom/lib-idempotent.sh
- [x] T006 Implement `verify_sbom_identical()` function for hash comparison in scripts/sbom/lib-idempotent.sh
- [x] T007 Implement `write_sbom_metadata()` function to persist metadata.json in scripts/sbom/lib-idempotent.sh
- [x] T008 Implement `should_overwrite_sbom()` function for idempotency decision logic in scripts/sbom/lib-idempotent.sh
- [x] T009 [P] Add helper functions for operation status logging in scripts/sbom/lib-idempotent.sh
- [x] T010 [P] Add error handling and validation for concurrent access (atomic rename, retry logic) in scripts/sbom/lib-idempotent.sh

---

## Phase 3: User Story 1 - Generate SBOM for New Image (P1)

> **Story Goal**: Enable initial SBOM generation for newly built images without prior artifacts  
> **Why This Priority**: Foundation of entire feature—without this, idempotency cannot exist  
> **Independent Test Criteria**:
> - Running `make sbom TAG=test` on fresh image creates SBOM files
> - Output contains both CycloneDX JSON and SPDX JSON formats
> - Metadata.json created with operation=GENERATED
> - Exit code 0 (success)
> - Works for both linux/amd64 and linux/arm64 architectures

- [x] T011 [US1] Enhance scripts/sbom/generate-sbom.sh to source lib-idempotent.sh at startup
- [x] T012 [US1] Add platform detection logic to generate-sbom.sh for architecture-specific paths
- [x] T013 [US1] Add SBOM file existence check in generate-sbom.sh before Syft invocation
- [x] T014 [US1] Generate both CycloneDX and SPDX format SBOMs via generate-sbom.sh
- [x] T015 [US1] Call write_sbom_metadata() to persist metadata.json with GENERATED operation in generate-sbom.sh
- [x] T016 [US1] Add success logging showing operation status and file paths to generate-sbom.sh
- [x] T017 [US1] Update Makefile sbom target help text to document new metadata.json output
- [x] T018 [US1] Test US1 acceptance scenario: Fresh image generates SBOM successfully with valid JSON

---

## Phase 4: User Story 2 - Idempotent SBOM Generation (P1)

> **Story Goal**: Enable re-running SBOM generation for same image digest without conflicts  
> **Why This Priority**: Directly fixes issue #14 ("cannot overwrite digest" error). Critical for production CI/CD  
> **Independent Test Criteria**:
> - Run `make sbom TAG=test` twice on same image
> - Both invocations exit with code 0 (no errors)
> - Second invocation reports operation=VERIFIED_IDENTICAL
> - SBOM file NOT overwritten (same file as first run)
> - Metadata.json updated with new timestamp, same content_hash
> - No "overwrite" or "conflict" error messages

- [x] T019 [US2] Add hash verification logic to generate-sbom.sh after SBOM generation
- [x] T020 [US2] Call verify_sbom_identical() in generate-sbom.sh to compare with existing metadata
- [x] T021 [US2] Implement decision branch in generate-sbom.sh: if hash matches → VERIFIED_IDENTICAL, skip overwrite
- [x] T022 [US2] Update metadata.json with operation=VERIFIED_IDENTICAL when hashes match in generate-sbom.sh
- [x] T023 [US2] Update Makefile sbom target to display operation status (GENERATED vs VERIFIED_IDENTICAL)
- [x] T024 [US2] Add new smoke test target `make sbom-idempotent-test` to Makefile for testing idempotency
- [x] T025 [US2] Smoke test validates: Run sbom twice, verify both succeed with 0 exit code
- [x] T026 [US2] Test US2 acceptance scenario: Regenerate SBOM for same digest, operation=VERIFIED_IDENTICAL

---

## Phase 5: User Story 3 - Update SBOM When Image Changes (P2)

> **Story Goal**: Replace SBOM when image contents change (new dependencies, code changes)  
> **Why This Priority**: Important for ongoing maintenance, but secondary to idempotency fix  
> **Independent Test Criteria**:
> - Build image with version A, generate SBOM (digest A, hash A)
> - Modify Dockerfile or dependencies, rebuild image (new digest B, new hash B)
> - Run SBOM generation again for new image
> - New SBOM file replaces old one (operation=UPDATED)
> - Metadata.json reflects new digest B and new hash B
> - Exit code 0 (success)
> - Old SBOM discarded (filesystem cleanup automatic)

- [ ] T027 [US3] Add hash mismatch detection logic in generate-sbom.sh
- [ ] T028 [US3] Implement UPDATED operation path in generate-sbom.sh (overwrite SBOM, update metadata)
- [ ] T029 [US3] Update metadata.json operation field to UPDATED when content differs in generate-sbom.sh
- [ ] T030 [US3] Add logging to show "SBOM updated" message with diff in component count (if available)
- [ ] T031 [US3] Update Makefile sbom target help to document UPDATED operation
- [ ] T032 [US3] Test US3 acceptance scenario: Rebuild image, regenerate SBOM, verify operation=UPDATED
- [ ] T033 [US3] Validate: Old SBOM replaced with new version, metadata reflects change

---

## Phase 6: User Story 4 - SBOM Generation in CI/CD Pipeline (P2)

> **Story Goal**: Integrate SBOM generation into GitHub Actions workflow for automated builds  
> **Why This Priority**: Validates feature works in CI/CD environment, but P1 stories must work first  
> **Independent Test Criteria**:
> - Push to feature branch triggers GitHub Actions workflow
> - Workflow builds multi-arch images and generates SBOMs
> - Workflow completes successfully on first run (new digests)
> - Workflow completes successfully on second push with same source (idempotent)
> - No "overwrite" or digest conflict errors in CI logs
> - SBOMs available as artifacts for compliance audit
> - Multi-arch builds (amd64 + arm64) each have separate SBOMs, no conflicts

- [ ] T034 [US4] [P] Update .github/workflows/build.yml to add SBOM generation step after image build
- [ ] T035 [US4] Add `make sbom-multi TAG=$(git describe --tags)` to GitHub Actions workflow
- [ ] T036 [US4] Configure GitHub Actions to upload build/sbom/ as artifacts for compliance records
- [ ] T037 [US4] Add workflow step to log SBOM operation status (GENERATED/VERIFIED_IDENTICAL/UPDATED)
- [ ] T038 [US4] Add workflow validation: SBOM generation must not fail (non-zero exit code fails build)
- [ ] T039 [US4] Test US4: Push to branch, verify workflow runs and generates SBOMs successfully
- [ ] T040 [US4] Test US4: Push same source again, verify workflow runs and idempotent SBOM generation succeeds
- [ ] T041 [US4] Validate: SBOM artifacts available in GitHub Actions artifacts for download

---

## Phase 7: Documentation & Cross-Cutting Concerns

> **Goal**: Ensure feature is documented, maintainable, and meets project standards  
> **Independent Test**: README updated, help text clear, no warnings or linting errors

- [ ] T042 [P] Update README.md with SBOM generation section and example usage
- [ ] T043 [P] Document Makefile targets: `make sbom`, `make sbom-multi`, `make sbom-idempotent-test`
- [ ] T044 Add inline comments to scripts/sbom/generate-sbom.sh explaining idempotency logic
- [ ] T045 Add inline comments to scripts/sbom/lib-idempotent.sh documenting each function contract
- [ ] T046 [P] Update scripts/sbom/README.md with operation types (GENERATED, VERIFIED_IDENTICAL, UPDATED)
- [ ] T047 Update CHANGELOG.md with SBOM generation enhancement and issue #14 fix
- [ ] T048 Validate shell scripts for syntax errors and linting (shellcheck) in scripts/sbom/
- [ ] T049 Run final smoke test: `make sbom TAG=latest` and `make sbom-multi TAG=latest` both succeed
- [ ] T050 Run final validation: `make sbom-idempotent-test` confirms idempotency working

---

## Summary: Tasks by User Story

| User Story | Phase | Count | Status |
|------------|-------|-------|--------|
| **Setup** | Phase 1 | 3 | Ready |
| **Foundational** | Phase 2 | 7 | Ready |
| **US1: New Image** | Phase 3 | 8 | Ready |
| **US2: Idempotent** | Phase 4 | 8 | Ready |
| **US3: Update** | Phase 5 | 7 | Ready |
| **US4: CI/CD** | Phase 6 | 8 | Ready |
| **Polish** | Phase 7 | 9 | Ready |
| **TOTAL** | - | **50** | **Ready for Implementation** |

---

## Estimated Effort

| Phase | Tasks | Complexity | Est. Hours |
|-------|-------|------------|-----------|
| Phase 1: Setup | 3 | Low | 0.5 |
| Phase 2: Foundational | 7 | Medium | 3 |
| Phase 3: US1 | 8 | Medium | 4 |
| Phase 4: US2 | 8 | High | 6 |
| Phase 5: US3 | 7 | Low | 2 |
| Phase 6: US4 | 8 | Medium | 3 |
| Phase 7: Polish | 9 | Low | 2 |
| **TOTAL** | **50** | - | **~20 hours** |

---

## Implementation Strategy

### MVP Scope (Recommended for First Release)

**Phases 1-4** (17 tasks, ~13 hours):
- ✅ Setup & foundational utilities
- ✅ US1: New image SBOM generation
- ✅ US2: Idempotent SBOM (core fix for issue #14)

**Delivers**: Basic idempotent SBOM generation, fixing the "cannot overwrite digest" error

### Extended Scope (Second Release)

**Phases 5-6** (15 tasks, ~5 hours):
- ✅ US3: Update SBOM on image changes
- ✅ US4: CI/CD integration
- ✅ Multi-architecture validation in production

**Delivers**: Full production-ready feature with CI/CD automation

### Full Feature (Third Release)

**Phase 7** (9 tasks, ~2 hours):
- ✅ Documentation
- ✅ Linting & validation
- ✅ Final smoke tests

**Delivers**: Production-ready, fully documented, polished feature

---

## Quality Gates

Before merging to `main`:

- [ ] All 50 tasks completed and tested
- [ ] US1 acceptance scenarios passing (new SBOM generation works)
- [ ] US2 acceptance scenarios passing (idempotent behavior works)
- [ ] `make sbom-idempotent-test` passes (smoke test for issue #14 fix)
- [ ] GitHub Actions workflow completes without errors
- [ ] No shell script linting errors (shellcheck passes)
- [ ] README updated with SBOM documentation
- [ ] CHANGELOG updated with feature description

---

## Notes

- **Backward Compatibility**: Feature enhances existing `generate-sbom.sh` without breaking changes
- **Non-Destructive**: SBOM verification is read-only until update is needed
- **Idempotent by Design**: Same image digest always produces same SBOM content
- **Multi-Arch Safe**: Each architecture (amd64, arm64) has independent SBOM, no conflicts
- **No New Dependencies**: Uses existing tools (Syft, jq, coreutils)
- **Platform-Agnostic**: Works on Linux, macOS, GitHub Actions runners

