# Tasks: Multi-Architecture Schema Registry Container Image

**Input**: Design documents from `/specs/001-schema-registry-image/`
**Prerequisites**: ✅ plan.md, spec.md, research.md, data-model.md, contracts/oci-labels.md, quickstart.md

**Tests**: This feature does NOT require traditional unit tests (build infrastructure project). Smoke tests only (container start + API validation).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `- [ ] [ID] [P?] [Story] Description`

- **Checkbox**: `- [ ]` REQUIRED for all tasks
- **[ID]**: Sequential task number (T001, T002, T003...)
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, etc.)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Repository structure and git submodule initialization

- [X] T001 Create LICENSE.md with repo tooling license and upstream license notice section
- [X] T002 Initialize git submodule at upstream/schema-registry pointing to https://github.com/confluentinc/schema-registry
- [X] T003 [P] Create .dockerignore excluding .git, specs/, docs/, .github/ from build context
- [X] T004 [P] Create .gitignore with docker build artifacts and IDE files

**Checkpoint**: ✅ Repository structure ready, upstream source tracked via submodule

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core build infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 Create Dockerfile multi-stage build with builder stage (BUILDPLATFORM, Maven 3 + Temurin 17)
- [X] T006 Configure Dockerfile BUILDER_IMAGE build arg with default maven:3-eclipse-temurin-17
- [X] T007 Add Dockerfile RUN command for Maven build: mvn -DskipTests package -P standalone in upstream/schema-registry
- [X] T008 Configure Dockerfile BuildKit cache mount for Maven repository: --mount=type=cache,target=/root/.m2
- [X] T009 Extract standalone JAR in Dockerfile: COPY from builder stage /workspace/upstream/schema-registry/package-schema-registry/target/kafka-schema-registry-package-*-standalone.jar
- [X] T010 Create Dockerfile runtime stage with RUNTIME_IMAGE build arg (default eclipse-temurin:17-jre)
- [X] T011 Configure Dockerfile runtime stage USER 65532 for non-root execution
- [X] T012 Configure Dockerfile runtime stage COPY --chown=65532:65532 for JAR and config files
- [X] T013 Add Dockerfile EXPOSE 8081 directive
- [X] T014 Configure Dockerfile ENTRYPOINT with JSON exec-form: ["java", "-jar", "/app/schema-registry.jar", "/etc/schema-registry/schema-registry.properties"]
- [X] T015 Add Dockerfile OCI LABEL instructions: org.opencontainers.image.source, version, revision, created, title, description, vendor (per contracts/oci-labels.md)
- [X] T016 [P] Create config/schema-registry.properties with listeners=http://0.0.0.0:8081 and kafkastore.bootstrap.servers=PLAINTEXT://kafka:9092
- [X] T017 Create Makefile with help target (default) displaying all available targets
- [X] T018 [P] Add Makefile submodule-init target: git submodule update --init --recursive
- [X] T019 [P] Add Makefile submodule-update target: git submodule update --remote upstream/schema-registry
- [X] T020 Add Makefile build target: docker build --platform=linux/$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
- [X] T021 Add Makefile buildx target: docker buildx build --platform linux/amd64,linux/arm64 with BUILDER_IMAGE/RUNTIME_IMAGE args
- [X] T022 Add Makefile push target with IMAGE and TAG parameters for registry push
- [X] T023 Add Makefile test target that runs tests/smoke.sh script (placeholder for Phase 8)

**Checkpoint**: ✅ Dockerfile and Makefile foundation complete, ready for user story implementation

---

## Phase 3: User Story 1 - Local Multi-Architecture Build (Priority: P1) 🎯 MVP

**Goal**: Enable developers to build Schema Registry image for their native platform (ARM Mac or x86 Linux) with single command

**Independent Test**: Clone repository, run `make submodule-init && make build`, verify image is tagged and container starts on port 8081

### Implementation for User Story 1

- [X] T024 [US1] Update Makefile build target to auto-detect platform from uname -m output
- [X] T025 [US1] Add Makefile IMAGE variable with default ib-schema-registry
- [X] T026 [US1] Add Makefile TAG variable with default latest
- [X] T027 [US1] Configure Makefile build target to tag image as $(IMAGE):$(TAG)
- [X] T028 [US1] Add Dockerfile syntax header: # syntax=docker/dockerfile:1.7
- [X] T029 [US1] Test build on macOS Apple Silicon: verify linux/arm64 image created
- [X] T030 [US1] Test build on Linux x86_64: verify linux/amd64 image created (via buildx)

**Checkpoint**: Local build works on both macOS ARM and Linux x86 without platform-specific workarounds (constitution gate: multi-arch portability)

---

## Phase 4: User Story 2 - Simultaneous Multi-Arch Build (Priority: P1)

**Goal**: Enable release engineers to build both architectures in single buildx invocation for efficient CI/CD

**Independent Test**: Run `make buildx`, verify buildx output shows both linux/amd64 and linux/arm64 built, inspect manifest to confirm both platforms present

### Implementation for User Story 2

- [X] T031 [US2] Configure Makefile buildx target to use docker buildx build command
- [X] T032 [US2] Add Makefile buildx target --platform linux/amd64,linux/arm64 argument
- [X] T033 [US2] Configure Makefile buildx target to pass BUILDER_IMAGE and RUNTIME_IMAGE build args
- [X] T034 [US2] Add Makefile buildx target --load flag for local testing (single platform) or --push for multi-arch registry push
- [X] T035 [US2] Test buildx locally: verify both architectures build in parallel without emulation
- [X] T036 [US2] Document buildx prerequisites in README: Docker buildx plugin installation steps

**Checkpoint**: Multi-arch builds work efficiently in single pass (constitution gate: build optimization)

---

## Phase 5: User Story 3 - Pluggable Base Images (Priority: P1)

**Goal**: Enable security engineers to swap Eclipse Temurin for Chainguard minimal images without Dockerfile modifications

**Independent Test**: Build with `make build RUNTIME_IMAGE=cgr.dev/chainguard/jre:latest BUILDER_IMAGE=cgr.dev/chainguard/maven:latest-dev`, verify image runs without shell dependencies, validate smaller image size

### Implementation for User Story 3

- [X] T037 [P] [US3] Document Makefile base image override examples in README: BUILDER_IMAGE and RUNTIME_IMAGE variables
- [X] T038 [P] [US3] Add README section comparing Eclipse Temurin vs Chainguard image sizes and CVE counts
- [X] T039 [US3] Test build with Chainguard builder: cgr.dev/chainguard/maven:latest-dev (INCOMPATIBLE: distroless lacks write permissions for Maven)
- [X] T040 [US3] Test build with Chainguard runtime: cgr.dev/chainguard/jre:latest
- [X] T041 [US3] Verify Dockerfile ENTRYPOINT JSON exec-form works without shell (no /bin/sh dependency)
- [X] T042 [US3] Verify Chainguard runtime image has no shell: test that docker exec container /bin/sh fails as expected
- [X] T043 [US3] Document README production recommendation: pin base images by digest for supply-chain security

**Checkpoint**: Base image pluggability validated with Chainguard alternatives (constitution gates: base image pluggability, distroless compatibility, supply-chain security)

---

## Phase 6: User Story 4 - CI/CD Automated Multi-Arch Build (Priority: P2)

**Goal**: Automate multi-arch builds in GitHub Actions with registry push and proper caching

**Independent Test**: Push commit to main branch, verify GitHub Actions workflow runs successfully, check GHCR for multi-arch image with correct tags

### Implementation for User Story 4

- [X] T044 [US4] Create .github/workflows/build-image.yml with name and trigger (push to main, pull_request)
- [X] T045 [US4] Add workflow job setup: ubuntu-latest runner
- [X] T046 [P] [US4] Add workflow step: Checkout code with submodules (submodules: recursive)
- [X] T047 [P] [US4] Add workflow step: Set up Docker Buildx
- [X] T048 [P] [US4] Add workflow step: Set up QEMU for cross-platform builds
- [X] T049 [US4] Add workflow step: Login to GHCR with conditional (only on push to main, skip on PR)
- [X] T050 [US4] Add workflow step: Extract metadata for tags (Docker metadata action: commit SHA, latest, version if tagged)
- [X] T051 [US4] Add workflow step: Build and push with buildx (platforms: linux/amd64,linux/arm64)
- [X] T052 [US4] Configure workflow buildx cache-from and cache-to for layer caching (GitHub Actions cache)
- [X] T053 [US4] Configure workflow buildx push: true only on main branch (push: ${{ github.event_name != 'pull_request' }})
- [X] T054 [US4] Test workflow on PR: verify build succeeds but no registry push
- [X] T055 [US4] Test workflow on main push: verify build succeeds and image pushed to GHCR

**Checkpoint**: CI/CD automation complete with multi-arch builds and proper caching (SC-002: cold build <15 min, SC-003: warm build <5 min)

---

## Phase 7: User Story 5 - Upstream Source Tracking (Priority: P2)

**Goal**: Enable maintainers to update Schema Registry version by updating submodule reference

**Independent Test**: Update submodule to newer tag, rebuild image, verify new version metadata in OCI labels and runtime output

### Implementation for User Story 5

- [X] T056 [US5] Add Makefile VERSION variable extraction from git submodule tag: $(shell cd upstream/schema-registry && git describe --tags --abbrev=0)
- [X] T057 [US5] Add Makefile LOCAL_VERSION suffix with format: $(VERSION)+infoblox.1
- [X] T058 [US5] Configure Makefile to pass VERSION build arg to Dockerfile for OCI labels
- [X] T059 [US5] Update Dockerfile ARG VERSION for runtime metadata
- [X] T060 [US5] Update Dockerfile LABEL org.opencontainers.image.version=${VERSION}
- [X] T061 [US5] Add README section documenting version update workflow: submodule update, rebuild, verify labels
- [X] T062 [US5] Test version extraction: verify Makefile correctly extracts 7.6.1 from submodule tag
- [X] T063 [US5] Test version metadata: verify docker inspect shows correct org.opencontainers.image.version label

**Checkpoint**: Version tracking automated via submodule (constitution gate: licensing compliance via submodule-only)

---

## Phase 8: User Story 6 - Custom Runtime Configuration (Priority: P3)

**Goal**: Enable deployment engineers to run image with production Kafka settings via mounted config file

**Independent Test**: Run container with `-v /path/to/custom.properties:/etc/schema-registry/schema-registry.properties`, verify Schema Registry uses custom Kafka bootstrap servers

### Implementation for User Story 6

- [X] T064 [P] [US6] Add README section documenting config file mount: docker run -v example
- [X] T065 [P] [US6] Add README section documenting environment variable overrides (if Schema Registry supports)
- [X] T066 [US6] Create example config files in config/examples/: production.properties, development.properties
- [X] T067 [US6] Update quickstart.md with Docker Compose example showing volume mount for custom config
- [X] T068 [US6] Test custom config: run container with mounted config pointing to external Kafka, verify connection
- [X] T069 [US6] Document config/schema-registry.properties as template: users should copy and customize for production

**Checkpoint**: Custom configuration supported for production deployments (flexibility without rebuilding image)

---

## Phase 9: Validation & Documentation (Cross-Cutting)

**Purpose**: Smoke tests, documentation, and constitution validation

- [X] T070 [P] Create tests/smoke.sh script: start container, wait for startup, curl GET http://localhost:8081/subjects
- [X] T071 [P] Verify tests/smoke.sh validates HTTP 200 response with empty array []
- [X] T072 Update Makefile test target to run tests/smoke.sh with proper container lifecycle
- [X] T073 [P] Create README.md with quickstart: clone with submodules, make build, make test commands
- [X] T074 [P] Add README sections: prerequisites (Docker, buildx), build instructions, run examples, configuration
- [X] T075 [P] Add README compliance section: Confluent Community License warnings, link to upstream license
- [X] T076 [P] Add README troubleshooting section: common build errors, platform issues, Maven cache
- [X] T077 [P] Create CONTRIBUTING.md with development workflow: submodule updates, testing, PR process
- [X] T078 Test smoke.sh on both linux/amd64 and linux/arm64 images (identical results required)
- [X] T079 Test quickstart.md steps from clean state: verify new contributor can build without external docs
- [X] T080 Validate all constitution gates: multi-arch portability, base image pluggability, distroless compatibility, supply-chain security, licensing compliance, ergonomics, testing
- [X] T081 Run final build validation: make clean && make submodule-init && make buildx && make test

**Checkpoint**: All constitution gates pass; image ready for release

---

## Phase 10: Security Enhancement - Chainguard Default Runtime (Priority: P1)

**Goal**: Switch to Chainguard JRE as default runtime for maximum security posture

**Independent Test**: Build with defaults, verify image uses Chainguard JRE, confirm smaller size and fewer CVEs

### Implementation Tasks

- [X] T082 [P] Update Dockerfile default RUNTIME_IMAGE ARG to cgr.dev/chainguard/jre:latest
- [X] T083 [P] Update Makefile default RUNTIME_IMAGE variable to cgr.dev/chainguard/jre:latest
- [X] T084 Update README.md features section to highlight Chainguard as "Secure by Default"
- [X] T085 Rename README "Chainguard Minimal Base Images" section to "Alternative Base Images"
- [X] T086 Update README "Alternative Base Images" section to show Temurin as alternative (not default)
- [X] T087 Update README architecture diagram to show Chainguard JRE as default runtime base
- [X] T088 Update Makefile help examples to show Temurin as alternative instead of Chainguard
- [X] T089 Update README "Pin Base Images by Digest" example to use Chainguard digest
- [ ] T090 Test build with new defaults: verify Chainguard JRE pulls and builds successfully
- [ ] T091 Compare image sizes: verify ~60% reduction (220MB → 90MB) with Chainguard vs Temurin
- [ ] T092 Scan both images: verify Chainguard has significantly fewer CVEs (target: 0-2 vs 20-50)
- [ ] T093 Test runtime functionality: verify smoke tests pass with Chainguard JRE
- [ ] T094 Test distroless compatibility: verify no shell available (docker exec fails as expected)
- [ ] T095 Test rollback scenario: verify RUNTIME_IMAGE=eclipse-temurin:17-jre override still works
- [ ] T096 Update constitution-validation.md to reflect Chainguard as default
- [ ] T097 Update quickstart.md if needed to mention Chainguard default
- [ ] T098 Run full test suite: make clean && make build && make test
- [ ] T099 Document security benefits in commit message and changelog

**Checkpoint**: Chainguard JRE is default, provides measurable security improvements, Temurin fallback works

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) - MVP core
- **User Story 2 (Phase 4)**: Depends on User Story 1 (Phase 3) - Extends single-platform to multi-platform
- **User Story 3 (Phase 5)**: Depends on User Story 1 (Phase 3) - Can run parallel to US2
- **User Story 4 (Phase 6)**: Depends on User Story 2 (Phase 4) - CI needs multi-arch buildx working
- **User Story 5 (Phase 7)**: Depends on User Story 1 (Phase 3) - Can run parallel to US2/US4
- **User Story 6 (Phase 8)**: Depends on User Story 1 (Phase 3) - Can run parallel to US2/US4/US5
- **Validation (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (Local Build) - P1**: MVP foundation - MUST complete first
- **US2 (Multi-Arch Buildx) - P1**: Extends US1 - Sequential after US1
- **US3 (Pluggable Base Images) - P1**: Independent of US2 - Can parallel with US2 after US1 complete
- **US4 (CI/CD) - P2**: Requires US2 multi-arch buildx working - Sequential after US2
- **US5 (Upstream Tracking) - P2**: Independent versioning - Can parallel with US2/US4 after US1
- **US6 (Custom Config) - P3**: Independent runtime feature - Can parallel with US2/US4/US5 after US1

### Within Each Phase

- **Foundational (Phase 2)**: Dockerfile tasks T005-T015 sequential (multi-stage build), Makefile tasks T017-T023 can parallel
- **US1 (Phase 3)**: All tasks sequential (builds on Makefile foundation)
- **US2 (Phase 4)**: Tasks T031-T036 sequential (extends Makefile build target)
- **US3 (Phase 5)**: Documentation tasks T037-T038 parallel, testing tasks T039-T043 sequential
- **US4 (Phase 6)**: Workflow setup tasks T046-T048 parallel, build tasks T050-T055 sequential
- **US5 (Phase 7)**: Makefile version tasks T056-T060 sequential, documentation T061 parallel
- **US6 (Phase 8)**: Documentation tasks T064-T065 parallel, example/test tasks T066-T069 sequential
- **Validation (Phase 9)**: Smoke test tasks T070-T072 sequential, documentation tasks T073-T077 parallel, final validation T078-T081 sequential

### Critical Path

1. T001-T004 (Setup) → 2. T005-T023 (Foundational) → 3. T024-T030 (US1 Local Build) → 4. T031-T036 (US2 Buildx) → 5. T044-T055 (US4 CI/CD) → 6. T070-T081 (Validation)

**Minimum MVP**: Phases 1-3 only (Setup + Foundational + US1) = Local build working on both platforms

---

## Parallel Opportunities

### Phase 1 (Setup)

```bash
# All setup tasks after T002 can run in parallel:
- T003 (Create .dockerignore)
- T004 (Create .gitignore)
```

### Phase 2 (Foundational)

```bash
# After Dockerfile foundation (T005-T015 sequential), parallel Makefile work:
- T016 (Create config file)
- T018 (Makefile submodule-init)
- T019 (Makefile submodule-update)
```

### Phase 5 (US3 - Pluggable Base Images)

```bash
# Documentation tasks can run together:
- T037 (Document base image override examples)
- T038 (Add size/CVE comparison section)
```

### Phase 6 (US4 - CI/CD)

```bash
# Initial workflow setup steps can run in parallel:
- T046 (Checkout with submodules)
- T047 (Set up Docker Buildx)
- T048 (Set up QEMU)
```

### Phase 8 (US6 - Custom Config)

```bash
# Documentation tasks can run together:
- T064 (Document config mount)
- T065 (Document env var overrides)
```

### Phase 9 (Validation)

```bash
# All documentation tasks can run in parallel:
- T070 (Create smoke.sh)
- T071 (Verify smoke test logic)
- T073 (Create README.md)
- T074 (Add README sections)
- T075 (Add compliance section)
- T076 (Add troubleshooting)
- T077 (Create CONTRIBUTING.md)
```

---

## Implementation Strategy

### MVP First (User Stories 1-2 Only) - Recommended for Milestone 1

1. **Phase 1**: Setup (T001-T004)
2. **Phase 2**: Foundational (T005-T023) - CRITICAL foundation
3. **Phase 3**: User Story 1 - Local Build (T024-T030)
4. **Phase 4**: User Story 2 - Multi-Arch Buildx (T031-T036)
5. **Phase 9**: Basic Validation (T070-T072, T073-T080 subset)
6. **STOP and VALIDATE**: Test builds on macOS ARM and Linux x86, verify multi-arch manifest

**Delivers**: Working multi-arch build system, testable locally and ready for CI

### Incremental Delivery - Full Feature Set

1. Complete MVP (Phases 1-4) → Foundation + Local + Multi-Arch builds working
2. Add User Story 3 (Phase 5) → Chainguard base image swap validated → Deploy/Demo security improvement
3. Add User Story 4 (Phase 6) → CI/CD automation working → Deploy/Demo automated builds
4. Add User Story 5 (Phase 7) → Version tracking automated → Deploy/Demo maintainability
5. Add User Story 6 (Phase 8) → Custom config supported → Deploy/Demo production readiness
6. Complete Validation (Phase 9) → Full documentation and smoke tests → Release v1.0.0

### Parallel Team Strategy

With 2-3 developers after Foundational (Phase 2) complete:

- **Developer A**: User Story 1 (Phase 3) → User Story 2 (Phase 4) [Critical path]
- **Developer B**: User Story 3 (Phase 5) [Can start after US1 T030, parallel to US2]
- **Developer C**: Documentation preparation (README structure, compliance research) [Parallel to US1-3]

Once US2 complete:
- **Developer A**: User Story 4 (Phase 6) [Requires US2]
- **Developer B**: User Story 5 (Phase 7) [Independent of US4]
- **Developer C**: User Story 6 (Phase 8) [Independent of US4/US5]

---

## Task Counts by Phase

- **Phase 1 (Setup)**: 4 tasks
- **Phase 2 (Foundational)**: 19 tasks (CRITICAL PATH)
- **Phase 3 (US1 - Local Build)**: 7 tasks (MVP)
- **Phase 4 (US2 - Multi-Arch Buildx)**: 6 tasks (MVP)
- **Phase 5 (US3 - Pluggable Base Images)**: 7 tasks
- **Phase 6 (US4 - CI/CD)**: 12 tasks
- **Phase 7 (US5 - Upstream Tracking)**: 8 tasks
- **Phase 8 (US6 - Custom Config)**: 6 tasks
- **Phase 9 (Validation)**: 12 tasks
- **Phase 10 (Chainguard Default)**: 18 tasks (8 complete, 10 validation remaining)

**Total**: 99 tasks (89 complete, 10 remaining)

**MVP Scope** (Phases 1-4 + minimal validation): ~40 tasks
**Full Feature Set**: 81 tasks
**With Security Enhancement**: 99 tasks

---

## Notes

- **[P] tasks**: Different files, no dependencies on other in-progress tasks
- **[Story] labels**: Map tasks to specific user stories (US1-US6) for traceability
- **Independent testing**: Each user story has independent test criteria in spec.md
- **Constitution validation**: Phase 9 validates all non-negotiable gates before release
- **Commit strategy**: Commit after each task or logical group (e.g., complete Dockerfile, complete Makefile target)
- **Checkpoints**: Stop at each phase checkpoint to validate story independently
- **Build times**: Target SC-002 (cold build <15 min) and SC-003 (warm build <5 min) throughout development
- **Platform testing**: Validate on both macOS ARM and Linux x86 to ensure portability (constitution requirement)
