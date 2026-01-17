# Tasks: SLSA Provenance Attestation

**Input**: Design documents from `/specs/001-slsa-provenance-attestation/`
**Prerequisites**: spec.md (user stories with priorities P1, P2, P3)

**Tests**: Not explicitly requested in specification - focusing on implementation and validation steps

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This project uses repository root structure:
- `.github/workflows/` for CI/CD workflows
- `docs/` for documentation
- `tests/` for test scripts
- `helm/ib-schema-registry/` for Helm chart

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Research and prepare provenance implementation approach

- [ ] T001 Research Docker buildx provenance generation capabilities and SLSA attestation format
- [ ] T002 [P] Research GitHub Actions OIDC token provider for attestation signing
- [ ] T003 [P] Document provenance verification workflow using cosign, slsa-verifier, and docker buildx imagetools

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core provenance infrastructure that MUST be complete before ANY user story implementation

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Add attestation permissions to build job in .github/workflows/build-image.yml (id-token: write, packages: write)
- [ ] T005 Configure docker/build-push-action@v5 provenance parameter in .github/workflows/build-image.yml
- [ ] T006 Add build-args for SLSA metadata (source URL, commit SHA, workflow ref) in .github/workflows/build-image.yml
- [ ] T007 Test provenance generation locally using docker buildx with --provenance=mode=max flag

**Checkpoint**: Foundation ready - provenance attestations can now be generated and attached to images

---

## Phase 3: User Story 1 - Container Image Provenance Verification (Priority: P1) 🎯 MVP

**Goal**: Enable security-conscious consumers to verify container image build provenance using SLSA framework to meet supply-chain security compliance requirements

**Independent Test**: Build an image through CI, then use cosign/slsa-verifier to extract and validate the attestation without requiring Helm chart functionality

### Implementation for User Story 1

- [ ] T008 [US1] Update docker/build-push-action@v5 step to enable provenance with mode=max in .github/workflows/build-image.yml
- [ ] T009 [US1] Configure provenance to generate separate attestations for linux/amd64 and linux/arm64 architectures in .github/workflows/build-image.yml
- [ ] T010 [US1] Add attestation-specific build-args (source repo URL, commit SHA, build workflow reference) in .github/workflows/build-image.yml
- [ ] T011 [US1] Ensure provenance attestations include build timestamp from metadata-action in .github/workflows/build-image.yml
- [ ] T012 [US1] Configure GitHub Actions OIDC identity for attestation signing in .github/workflows/build-image.yml
- [ ] T013 [US1] Add post-build validation step to verify attestation attachment in .github/workflows/build-image.yml
- [ ] T014 [P] [US1] Create verification documentation in docs/provenance-verification.md with cosign examples
- [ ] T015 [P] [US1] Add slsa-verifier usage examples in docs/provenance-verification.md
- [ ] T016 [P] [US1] Add docker buildx imagetools inspect examples in docs/provenance-verification.md
- [ ] T017 [P] [US1] Document multi-arch attestation verification workflow in docs/provenance-verification.md
- [ ] T018 [P] [US1] Document offline/air-gapped verification scenarios in docs/provenance-verification.md
- [ ] T019 [US1] Update README.md with link to provenance verification documentation
- [ ] T020 [US1] Add provenance verification quickstart section to README.md

**Checkpoint**: At this point, container images have provenance attestations that can be independently verified using standard tools

---

## Phase 4: User Story 2 - Provenance Integration in CI Pipeline (Priority: P2)

**Goal**: Automate provenance generation for all builds without breaking existing workflows, ensuring all published images include supply-chain metadata by default

**Independent Test**: Trigger a CI build (push to main or tag creation) and validate that the build completes successfully with attestations attached

### Implementation for User Story 2

- [ ] T021 [US2] Add conditional logic to skip provenance generation for pull_request events in .github/workflows/build-image.yml
- [ ] T022 [US2] Implement error handling to distinguish build failures from attestation failures in .github/workflows/build-image.yml
- [ ] T023 [US2] Add attestation generation logging to build workflow for debugging in .github/workflows/build-image.yml
- [ ] T024 [US2] Update build job to continue using existing QEMU setup without conflicts in .github/workflows/build-image.yml
- [ ] T025 [US2] Verify multi-arch build with cache-from/cache-to still functions with provenance in .github/workflows/build-image.yml
- [ ] T026 [US2] Test provenance generation with release tag workflow triggers in .github/workflows/build-image.yml
- [ ] T027 [US2] Add provenance validation to test job that verifies attestations exist in .github/workflows/build-image.yml
- [ ] T028 [P] [US2] Create troubleshooting guide for provenance generation failures in docs/troubleshooting-provenance.md
- [ ] T029 [P] [US2] Document provenance behavior for different CI triggers (push, tag, PR) in docs/ci-provenance-guide.md
- [ ] T030 [US2] Update CONTRIBUTING.md with provenance testing instructions for contributors

**Checkpoint**: At this point, CI automatically generates and attaches provenance attestations for all push/tag events without manual intervention

---

## Phase 5: User Story 3 - Helm Chart Provenance (Priority: P3)

**Goal**: Enable Kubernetes administrators to verify Helm chart build provenance to validate the entire deployment stack's supply-chain integrity

**Independent Test**: Package and publish a Helm chart through CI, then verify the chart's provenance attestation using Helm or OCI registry verification tools

### Implementation for User Story 3

- [ ] T031 [US3] Research Helm chart provenance attestation mechanisms for OCI registries
- [ ] T032 [US3] Add Helm chart packaging workflow with provenance generation in .github/workflows/build-image.yml or new workflow
- [ ] T033 [US3] Configure Helm provenance to include chart source repository URL and commit SHA
- [ ] T034 [US3] Configure Helm provenance to include chart version from Chart.yaml
- [ ] T035 [US3] Add attestation signing for Helm chart artifacts using GitHub OIDC
- [ ] T036 [US3] Test Helm chart provenance attachment to OCI registry (ghcr.io)
- [ ] T037 [P] [US3] Document Helm chart provenance verification using Helm tooling in docs/helm-provenance-verification.md
- [ ] T038 [P] [US3] Document Helm chart provenance verification using OCI registry tools in docs/helm-provenance-verification.md
- [ ] T039 [US3] Update helm/ib-schema-registry/README.md with provenance verification instructions
- [ ] T040 [US3] Add Helm chart provenance verification to helm-e2e job in .github/workflows/build-image.yml

**Checkpoint**: All artifacts (container images and Helm charts) now include verifiable SLSA provenance attestations

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, and compliance improvements

- [ ] T041 [P] Add provenance verification to smoke test script in tests/smoke.sh
- [ ] T042 [P] Create automated provenance validation script in tests/validate-provenance.sh
- [ ] T043 [P] Document GitHub Container Registry attestation storage behavior in docs/registry-attestation-limits.md
- [ ] T044 [P] Add provenance section to LICENSE.md regarding attestation signing
- [ ] T045 Update CHANGELOG.md with SLSA provenance attestation feature details
- [ ] T046 Add provenance feature to main README.md features list
- [ ] T047 [P] Create example queries for inspecting attestations in docs/provenance-examples.md
- [ ] T048 [P] Document build matrix provenance behavior if using matrix builds in docs/ci-provenance-guide.md
- [ ] T049 Update constitution validation to verify provenance implementation aligns with §IV supply-chain security requirements
- [ ] T050 Run end-to-end validation of all three user stories using quickstart workflows

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - research can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User Story 1 (P1) can proceed independently after Phase 2
  - User Story 2 (P2) depends on User Story 1 completion (builds on P1 infrastructure)
  - User Story 3 (P3) can proceed after Phase 2 (independent of P1/P2 but follows MVP pattern)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Depends on User Story 1 - Builds automation on top of P1's manual provenance generation
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Independent of P1/P2 (different artifact type)

### Within Each User Story

- **User Story 1**: Attestation generation → verification documentation → README updates
- **User Story 2**: Conditional logic → error handling → validation → documentation
- **User Story 3**: Research → implementation → verification → documentation

### Parallel Opportunities

- T001, T002, T003 can run in parallel (Phase 1 research tasks)
- T014, T015, T016, T017, T018 can run in parallel (US1 documentation tasks)
- T028, T029 can run in parallel (US2 documentation tasks)
- T037, T038 can run in parallel (US3 documentation tasks)
- T041, T042, T043, T044, T047, T048 can run in parallel (Phase 6 documentation tasks)

---

## Parallel Example: User Story 1 Documentation

```bash
# Launch all documentation tasks for User Story 1 together:
Task: "Create verification documentation in docs/provenance-verification.md with cosign examples"
Task: "Add slsa-verifier usage examples in docs/provenance-verification.md"
Task: "Add docker buildx imagetools inspect examples in docs/provenance-verification.md"
Task: "Document multi-arch attestation verification workflow in docs/provenance-verification.md"
Task: "Document offline/air-gapped verification scenarios in docs/provenance-verification.md"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (Research)
2. Complete Phase 2: Foundational (CRITICAL - enables provenance generation)
3. Complete Phase 3: User Story 1 (Container image provenance)
4. **STOP and VALIDATE**: Test provenance verification independently using cosign/slsa-verifier
5. Deploy/demo if ready - images now have verifiable provenance

### Incremental Delivery

1. Complete Setup + Foundational → Provenance generation infrastructure ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP - verifiable images!)
3. Add User Story 2 → Test independently → Deploy/Demo (Full automation!)
4. Add User Story 3 → Test independently → Deploy/Demo (Complete supply-chain coverage!)
5. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (container image provenance)
   - Developer B: User Story 3 (Helm chart provenance - independent)
3. Once User Story 1 is complete:
   - Developer A: User Story 2 (CI automation building on P1)
4. Stories complete and integrate independently

---

## Validation & Success Criteria

### Per User Story Validation

**User Story 1 (P1)**:
- ✅ Build image in CI and verify provenance attestation exists for both linux/amd64 and linux/arm64
- ✅ Use cosign to verify attestation signature using GitHub OIDC identity
- ✅ Use slsa-verifier to validate SLSA build metadata completeness
- ✅ Verify attestation includes source repo URL, commit SHA, workflow reference, timestamp
- ✅ Execute verification in under 30 seconds using provided documentation

**User Story 2 (P2)**:
- ✅ Push to main branch and verify all published images include attestations
- ✅ Create release tag and verify release images include attestations with tag version
- ✅ Build pull request and verify provenance generation doesn't block build
- ✅ Verify existing build steps (QEMU, multi-arch, cache) continue functioning
- ✅ Review failed build logs and confirm failure reasons are clearly indicated
- ✅ Verify build time increase is ≤10% compared to pre-provenance baseline

**User Story 3 (P3)**:
- ✅ Publish Helm chart and verify provenance attestation exists in OCI registry
- ✅ Verify chart attestation includes source repo URL, commit SHA, chart version
- ✅ Use Helm or OCI tooling to verify attestation using provided documentation

### Edge Case Coverage

- ✅ Multi-arch manifest attestation: Each architecture has separate attestation (T009)
- ✅ PR builds without push: Provenance skipped gracefully (T021)
- ✅ Registry attestation storage: Documented limits and guidance (T043)
- ✅ Offline verification: Air-gapped workflows documented (T018)
- ✅ Build matrix provenance: Each output gets separate attestation (T048)
- ✅ Helm OCI vs HTTP: Provenance distribution documented (T038)

---

## Notes

- [P] tasks = different files, no dependencies - can run in parallel
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Focus on using Docker buildx built-in provenance features per SPR-004 requirement
- Maintain multi-arch support per constitution §II (non-negotiable)
- Align with constitution §IV supply-chain security requirements
- No modifications to Dockerfile or runtime image per SPR-005
