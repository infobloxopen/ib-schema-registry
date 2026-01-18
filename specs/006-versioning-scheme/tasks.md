# Implementation Tasks: Unified Versioning Scheme

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)  
**Status**: Ready for Implementation

## Task Execution Order

Tasks are organized by phase and must be executed in order within each phase. Tasks marked [P] can be executed in parallel with other [P] tasks in the same phase.

---

## Phase 0: Research & Design (Foundation)

### T001: Create research.md
- [X] Document semver prerelease vs build metadata comparison
- [X] Research OCI registry tag character restrictions  
- [X] Document docker metadata-action compatibility
- [X] Research Helm chart version field semver requirements
- [X] Define git tag naming conventions for releases
- **Files**: `specs/006-versioning-scheme/research.md`
- **Dependencies**: None
- **Validation**: Document created with all sections complete

### T002: Create data-model.md
- [X] Define Version String entity with format and validation rules
- [X] Define Upstream Version extraction algorithm
- [X] Define SHA computation method
- [X] Define Dirty detection logic
- [X] Define Branch name sanitization rules
- **Files**: `specs/006-versioning-scheme/data-model.md`
- **Dependencies**: T001
- **Validation**: All entities documented with examples

### T003: Create contracts/version-format.md [P]
- [X] Define regex pattern for valid version strings
- [X] Provide examples for each scenario (release, main, feature, dirty)
- [X] Document character set restrictions
- [X] Document maximum length constraints
- **Files**: `specs/006-versioning-scheme/contracts/version-format.md`
- **Dependencies**: T002
- **Validation**: Contract document with test cases

### T004: Audit codebase for version usage [P]
- [X] Grep for VERSION, TAG, +infoblox, metadata-action references
- [X] Document all files that reference versioning
- [X] Identify Makefile variables to update
- [X] Identify workflow steps to update
- **Files**: Audit notes (can be inline or separate file)
- **Dependencies**: None
- **Validation**: Complete list of files to modify

---

## Phase 1: Version Computation Script (Core Logic)

### T005: Create scripts/version.sh structure
- [X] Create executable script file with proper shebang
- [X] Add get_upstream_version() function
- [X] Add get_short_sha() function
- [X] Add detect_dirty() function
- [X] Add get_branch_name() function
- [X] Add sanitize_branch() function
- **Files**: `scripts/version.sh`
- **Dependencies**: T002
- **Validation**: Script exists, is executable, functions defined

### T006: Implement version computation logic
- [X] Implement release tag detection and parsing
- [X] Implement main branch version format
- [X] Implement feature branch version format with sanitization
- [X] Add compute_version() main entry point
- **Files**: `scripts/version.sh`
- **Dependencies**: T005
- **Validation**: All version scenarios produce correct format

### T007: Add output format modes
- [X] Implement --format=export (shell variables)
- [X] Implement --format=json (JSON object)
- [X] Implement --format=make (Makefile syntax)
- [X] Implement --format=github (GH Actions output)
- [X] Implement default plain TAG output
- **Files**: `scripts/version.sh`
- **Dependencies**: T006
- **Validation**: Each format produces correct output

### T008: Handle edge cases
- [X] Handle missing upstream submodule (fallback or error)
- [X] Handle git tag without -ib.N suffix (default to -ib.1)
- [X] Handle detached HEAD state
- [X] Handle shallow clone (ensure git describe works)
- **Files**: `scripts/version.sh`
- **Dependencies**: T007
- **Validation**: Edge case tests pass

### T009: Add validate_version() function
- [X] Check character set [A-Za-z0-9_.-]
- [X] Verify semver prerelease format with regex
- [X] Add maximum length check (255 chars)
- [X] Return proper exit codes
- **Files**: `scripts/version.sh`
- **Dependencies**: T006
- **Validation**: Validation catches invalid versions

### T010: Create scripts/validate-version.sh [P]
- [X] Create wrapper script for external validation
- [X] Use semver tool if available (optional)
- [X] Validate against version format contract
- [X] Output human-readable error messages
- **Files**: `scripts/validate-version.sh`
- **Dependencies**: T003, T009
- **Validation**: Script validates versions correctly

---

## Phase 2: Makefile Integration (Local Build Support)

### T011: Update Makefile version variables
- [X] Add COMPUTED_VERSION variable using version.sh
- [X] Replace old VERSION extraction logic
- [X] Replace LOCAL_VERSION references with VERSION
- [X] Add UPSTREAM_VERSION variable
- **Files**: `Makefile`
- **Dependencies**: T007
- **Validation**: make shows correct VERSION value

### T012: Remove LOCAL_VERSION variable
- [X] Remove LOCAL_VERSION definition
- [X] Replace all LOCAL_VERSION references with VERSION
- [X] Update BUILD_ARGS to use VERSION consistently
- [X] Update OCI labels to use new version format
- **Files**: `Makefile`
- **Dependencies**: T011
- **Validation**: No LOCAL_VERSION references remain

### T013: Add make version target
- [X] Create version target that displays computed version info
- [X] Show all version components in readable format
- [X] Mark as .PHONY
- **Files**: `Makefile`
- **Dependencies**: T011
- **Validation**: make version displays version info

### T014: Add make version-validate target [P]
- [X] Create version-validate target
- [X] Call validate-version.sh with computed VERSION
- [X] Mark as .PHONY
- **Files**: `Makefile`
- **Dependencies**: T010, T013
- **Validation**: make version-validate passes

### T015: Update make help output [P]
- [X] Add version targets to help text
- [X] Update examples to show new version format
- [X] Document VERSION override capability
- **Files**: `Makefile`
- **Dependencies**: T013
- **Validation**: make help shows version targets

### T016: Test Makefile changes
- [X] Test make version from main branch
- [X] Test make version from feature branch
- [X] Test make version with dirty tree
- [X] Test make build VERSION=custom override
- **Files**: None (testing)
- **Dependencies**: T011-T015
- **Validation**: All test scenarios pass

---

## Phase 3: GitHub Actions Workflow Updates (CI/CD Integration)

### T017: Add version computation step to workflow
- [X] Add step that runs scripts/version.sh --format=github
- [X] Ensure script is executable (chmod)
- [X] Capture outputs: VERSION, UPSTREAM_VERSION, SHA, DIRTY, TAG
- **Files**: `.github/workflows/build-image.yml`
- **Dependencies**: T007
- **Validation**: Step produces correct outputs

### T018: Update docker/metadata-action configuration
- [X] Replace tag generation with computed TAG
- [X] Update latest tag logic
- [X] Update OCI labels with new version fields
- [X] Add org.infoblox.upstream.version label
- **Files**: `.github/workflows/build-image.yml`
- **Dependencies**: T017
- **Validation**: Metadata action uses computed version

### T019: Remove old version extraction step
- [X] Delete "Get upstream version" step
- [X] Remove upstream_version and local_version outputs
- [X] Update any references to old step outputs
- **Files**: `.github/workflows/build-image.yml`
- **Dependencies**: T018
- **Validation**: Old step completely removed

### T020: Update Docker build step
- [X] Update VERSION build arg to use computed TAG
- [X] Update UPSTREAM_VERSION build arg
- [X] Update REVISION build arg to use computed SHA
- **Files**: `.github/workflows/build-image.yml`
- **Dependencies**: T017
- **Validation**: Build uses correct version args

### T021: Update Helm chart packaging step
- [X] Use computed TAG for Chart.yaml version field
- [X] Use UPSTREAM_VERSION for appVersion field
- [X] Update sed commands to use new version values
- [X] Add comment explaining version vs appVersion
- **Files**: `.github/workflows/build-image.yml`
- **Dependencies**: T017
- **Validation**: Chart uses correct versions

### T022: Remove branch name transformation logic
- [X] Delete 0.0.0-${VERSION} transformation code
- [X] Remove SHORT_SHA extraction (now in version script)
- [X] Simplify Helm chart version logic
- **Files**: `.github/workflows/build-image.yml`
- **Dependencies**: T021
- **Validation**: Transformation logic removed

### T023: Add version validation step [P]
- [X] Add step that runs validate-version.sh
- [X] Validate computed TAG format
- [X] Fail build if validation fails
- **Files**: `.github/workflows/build-image.yml`
- **Dependencies**: T010, T017
- **Validation**: Validation step exists and works

### T024: Update workflow comments and documentation [P]
- [X] Add comments explaining new version scheme
- [X] Document why + is avoided (OCI compatibility)
- [X] Link to versioning documentation
- **Files**: `.github/workflows/build-image.yml`
- **Dependencies**: T017-T023
- **Validation**: Comments added and accurate

---

## Phase 4: Documentation Updates (User-Facing)

### T025: Add Versioning section to README.md
- [ ] Add comprehensive Versioning section after Kubernetes Deployment
- [ ] Explain version format with examples
- [ ] Explain why + is not used (OCI compatibility)
- [ ] Document version components
- [ ] Add "make version" command example
- **Files**: `README.md`
- **Dependencies**: T013
- **Validation**: Section complete with all examples

### T026: Update installation examples in README.md [P]
- [ ] Replace old docker pull examples with new version format
- [ ] Replace old helm install examples with new version format
- [ ] Update all version references to use new format
- **Files**: `README.md`
- **Dependencies**: T025
- **Validation**: All examples use new format

### T027: Update CONTRIBUTING.md release process
- [ ] Document new git tag naming convention (v<upstream>-ib.<n>)
- [ ] Explain how to determine upstream version
- [ ] Explain how to increment revision number
- [ ] Update release creation steps
- [ ] Document CI build behavior
- **Files**: `CONTRIBUTING.md`
- **Dependencies**: T002
- **Validation**: Release process documented clearly

### T028: Create docs/versioning.md comprehensive guide
- [ ] Detailed format specification
- [ ] Version component breakdown
- [ ] Semver sorting behavior explanation
- [ ] FAQ section (Why no +? How to find commit?)
- [ ] Troubleshooting guide
- **Files**: `docs/versioning.md`
- **Dependencies**: T001, T002, T003
- **Validation**: Comprehensive guide created

### T029: Update helm/ib-schema-registry/README.md [P]
- [ ] Replace version examples with new format
- [ ] Add section explaining Chart version vs appVersion
- [ ] Document version synchronization with Docker image
- **Files**: `helm/ib-schema-registry/README.md`
- **Dependencies**: T025
- **Validation**: Helm docs updated

### T030: Update helm/ib-schema-registry/values.yaml comments [P]
- [ ] Update image.tag comment to explain appVersion tracking
- [ ] Explain difference between upstream version and full version
- [ ] Add example showing version relationship
- **Files**: `helm/ib-schema-registry/values.yaml`
- **Dependencies**: T025
- **Validation**: Comments clarify versioning

---

## Phase 5: Remove Old Versioning References (Cleanup)

### T031: Search and replace +infoblox references
- [ ] Grep for all +infoblox occurrences
- [ ] Replace with new format or remove
- [ ] Update any hardcoded version examples
- **Files**: Multiple (identified in T004)
- **Dependencies**: T004, T025-T030
- **Validation**: No +infoblox references remain

### T032: Remove LOCAL_VERSION from all files
- [ ] Verify Makefile removal (from T012)
- [ ] Remove from any scripts or documentation
- [ ] Update any comments mentioning LOCAL_VERSION
- **Files**: Multiple (identified in T004)
- **Dependencies**: T012
- **Validation**: No LOCAL_VERSION references remain

### T033: Update Dockerfile version labels [P]
- [ ] Update VERSION label if needed
- [ ] Add UPSTREAM_VERSION label
- [ ] Ensure labels match OCI spec
- **Files**: `Dockerfile`
- **Dependencies**: T020
- **Validation**: Labels use new version format

### T034: Review metadata-action tag configuration [P]
- [ ] Verify semver tags are appropriate or remove
- [ ] Ensure tag list matches requirements
- [ ] Document tag strategy in comments
- **Files**: `.github/workflows/build-image.yml`
- **Dependencies**: T018
- **Validation**: Tag configuration optimal

### T035: Update CHANGELOG.md [P]
- [ ] Add entry documenting version scheme change
- [ ] Note breaking change for release process
- [ ] Link to migration documentation
- **Files**: `CHANGELOG.md` (if exists)
- **Dependencies**: T028
- **Validation**: Changelog entry added

### T036: Update issue templates [P]
- [ ] Replace example versions with new format
- [ ] Update version-related questions
- **Files**: `.github/ISSUE_TEMPLATE/*` (if exists)
- **Dependencies**: T025
- **Validation**: Templates use new format

---

## Phase 6: Testing & Validation (Quality Assurance)

### T037: Create scripts/test-version.sh
- [ ] Create unit test script for version.sh
- [ ] Test main branch version format
- [ ] Test release tag version format
- [ ] Test feature branch version format
- [ ] Test dirty detection
- [ ] Test branch sanitization
- **Files**: `scripts/test-version.sh`
- **Dependencies**: T006-T009
- **Validation**: Test script passes all tests

### T038: Add version validation to CI
- [ ] Add workflow step to validate version format
- [ ] Check character set compliance
- [ ] Check semver prerelease format
- [ ] Log computed version for debugging
- **Files**: `.github/workflows/build-image.yml`
- **Dependencies**: T023
- **Validation**: CI validation step exists

### T039: Test local builds
- [ ] Test make version on main branch
- [ ] Test make version on feature branch
- [ ] Test make version with dirty tree
- [ ] Test make version with release tag
- [ ] Test make build with computed version
- **Files**: None (manual testing)
- **Dependencies**: T016
- **Validation**: All local build scenarios work

### T040: Test CI pipeline
- [ ] Push feature branch and verify version format
- [ ] Push to main and verify version format
- [ ] Create test tag and verify version format
- **Files**: None (CI testing)
- **Dependencies**: T017-T024
- **Validation**: CI builds succeed with correct versions

### T041: Validate OCI registry acceptance [P]
- [ ] Build test image with new version format
- [ ] Push to GHCR
- [ ] Pull image to verify
- **Files**: None (integration testing)
- **Dependencies**: T040
- **Validation**: GHCR accepts new version tags

### T042: Test Helm chart versioning [P]
- [ ] Verify Chart.yaml version matches Docker tag
- [ ] Verify appVersion shows upstream version
- [ ] Test helm install with new version format
- **Files**: None (integration testing)
- **Dependencies**: T021, T041
- **Validation**: Helm chart versions correct

---

## Phase 7: Migration & Rollout (Communication)

### T043: Create docs/migration-versioning.md
- [ ] Document what's changing (old vs new format)
- [ ] Explain why the change (OCI compatibility)
- [ ] Document impact on deployments
- [ ] Provide upgrade path
- [ ] Include before/after examples
- **Files**: `docs/migration-versioning.md`
- **Dependencies**: T028
- **Validation**: Migration guide complete

### T044: Update PR description [P]
- [ ] Document version scheme change
- [ ] Link to migration guide
- [ ] Highlight breaking change for release process
- **Files**: PR description (GitHub)
- **Dependencies**: T043
- **Validation**: PR clearly communicates changes

### T045: Create announcement draft [P]
- [ ] Explain necessity (OCI compatibility)
- [ ] Show before/after examples
- [ ] Link to documentation
- **Files**: Announcement (separate file or PR)
- **Dependencies**: T043
- **Validation**: Announcement ready

### T046: Plan backward compatibility [P]
- [ ] Decide if dual-format tagging needed
- [ ] Document deprecation timeline if applicable
- [ ] Update plan.md with decision
- **Files**: `specs/006-versioning-scheme/plan.md`
- **Dependencies**: T043
- **Validation**: Compatibility plan documented

### T047: Document testing results
- [ ] Summarize test results from T037-T042
- [ ] Document any issues found and resolved
- [ ] Create final validation checklist
- **Files**: `specs/006-versioning-scheme/quickstart.md` (update)
- **Dependencies**: T037-T042
- **Validation**: Test results documented

---

## Task Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Phase 0: Research | T001-T004 | Not Started |
| Phase 1: Version Script | T005-T010 | Not Started |
| Phase 2: Makefile | T011-T016 | Not Started |
| Phase 3: CI Workflow | T017-T024 | Not Started |
| Phase 4: Documentation | T025-T030 | Not Started |
| Phase 5: Cleanup | T031-T036 | Not Started |
| Phase 6: Testing | T037-T042 | Not Started |
| Phase 7: Migration | T043-T047 | Not Started |
| **Total** | **47 tasks** | **0% complete** |

## Execution Notes

- Tasks within a phase should generally be completed in order
- Tasks marked [P] can be done in parallel with other [P] tasks
- Each task should be marked complete (checkbox) when finished
- Test tasks (T016, T039-T042) should be re-run if earlier tasks are modified
- Phase 6 (Testing) may reveal issues requiring fixes in earlier phases
