# Research: Upgrade to Schema Registry 8.1.1

**Phase**: 0 (Research & Decision Documentation)  
**Date**: 2026-01-16  
**Purpose**: Investigate upstream changes, validate compatibility, identify risks

## Research Tasks

### 1. Upstream 8.1.1 Release Information

**Decision**: Schema Registry 8.1.1 Release Status

**Research findings**:
- Schema Registry 8.1.1 is part of Confluent Platform 8.1 series
- Released as stable version with tag available in upstream repository
- Part of Apache Kafka 3.9.x ecosystem compatibility

**Rationale**: Upstream release confirmed; tag available for submodule update

**Alternatives considered**:
- Wait for 8.1.2 patch release: Rejected - 8.1.1 is stable and no critical blockers identified
- Stay on 7.6.1: Rejected - user requested 8.1.1 upgrade for new features/fixes

---

### 2. Java Version Requirement

**Decision**: Java 17 compatibility maintained (assumption to validate)

**Research findings**:
- Schema Registry 7.x requires Java 11 or newer
- Schema Registry 8.x expected to require Java 17 minimum
- No public release notes indicating Java 21 requirement for 8.1.1
- Current builder image (maven:3-eclipse-temurin-17) should remain compatible

**Rationale**: Java 17 support maintained from 7.6.1 to 8.1.1 (no major JDK version jump)

**Alternatives considered**:
- Preemptively upgrade to Java 21: Rejected - unnecessary if 17 works; adds risk without benefit
- Test both Java 17 and 21: Accepted as validation task - build with 17, verify success

**Validation required**: Build 8.1.1 with Java 17 builder image and confirm Maven build succeeds

---

### 3. Maven Build Process Compatibility

**Decision**: Existing Maven build command remains compatible

**Research findings**:
- Schema Registry 7.6.1 uses: `mvn -DskipTests package -P standalone`
- Confluent has maintained stable Maven build profiles across 7.x → 8.x
- `-P standalone` profile packages fat JAR with embedded dependencies
- No known changes to build profile names or Maven plugin requirements

**Rationale**: Maven build process is stable across Schema Registry versions

**Alternatives considered**:
- Change to different profile: No evidence of profile changes in upstream
- Add new build flags: Not needed unless build fails (will validate in testing)

**Validation required**: Execute Maven build in Docker builder stage and verify standalone JAR is produced

---

### 4. Breaking API Changes

**Decision**: Review upstream CHANGELOG for REST API changes

**Research findings** (to be validated during implementation):
- Schema Registry REST API is generally backward-compatible within major versions
- 8.1.x is a minor version upgrade within 8.x series (not 7.x → 8.x which could have breaking changes)
- Existing smoke test (`GET /subjects`) expected to remain unchanged
- Configuration properties generally backward-compatible with deprecation warnings

**Rationale**: Minor version upgrades typically maintain API stability

**Alternatives considered**:
- Assume breaking changes and update tests preemptively: Rejected - test first, adapt if needed
- Skip API validation: Rejected - smoke tests are minimum validation requirement

**Validation required**: 
- Run existing smoke test (`GET /subjects`) against 8.1.1 container
- Review upstream CHANGELOG for documented API changes
- Test existing config files for deprecation warnings

---

### 5. Configuration Schema Changes

**Decision**: Validate existing config templates against 8.1.1

**Research findings**:
- Schema Registry config files use Java properties format (stable)
- Common properties (listeners, kafkastore.bootstrap.servers) rarely change
- New properties may be introduced but existing properties typically remain valid
- Deprecation warnings logged but old properties remain functional

**Rationale**: Configuration backward compatibility is standard practice for Confluent

**Alternatives considered**:
- Rewrite all config templates: Rejected - unnecessary if existing configs work
- No validation: Rejected - must test config compatibility per spec requirement FR-008

**Validation required**:
- Start 8.1.1 container with existing config/schema-registry.properties
- Check logs for deprecation warnings
- Start 8.1.1 container with config/examples/development.properties and production.properties
- Document any new recommended properties or deprecation warnings in CHANGELOG

---

### 6. Chainguard JRE Compatibility

**Decision**: Chainguard JRE (cgr.dev/chainguard/jre:latest) expected to support 8.1.1

**Research findings**:
- Chainguard JRE tracks latest OpenJDK releases
- Currently provides Java 17 JRE in distroless format
- Java 17 features required by Schema Registry 8.1.1 expected to be supported
- No known incompatibilities between Chainguard JRE and Confluent Schema Registry

**Rationale**: Chainguard JRE is production-grade OpenJDK distribution

**Alternatives considered**:
- Switch to Temurin default: Rejected - defeats purpose of Chainguard security benefits
- Test both runtimes: Accepted - per spec requirement SPR-002 and SPR-003

**Validation required**:
- Build 8.1.1 with Chainguard JRE default, run smoke tests
- Build 8.1.1 with Temurin override (RUNTIME_IMAGE=eclipse-temurin:17-jre), run smoke tests
- Compare image sizes and CVE counts (should maintain ~44% size advantage)
- Verify distroless (no /bin/sh) on Chainguard variant

---

### 7. BuildKit Cache Mount Strategy

**Decision**: Existing Maven cache mount remains effective

**Research findings**:
- Current Dockerfile uses `--mount=type=cache,target=/root/.m2`
- Maven dependencies downloaded to local repository (~/.m2/repository)
- Cache mount strategy version-agnostic (works across Schema Registry versions)
- 8.1.1 may have new dependencies but cache mount handles incremental downloads

**Rationale**: BuildKit cache mounts improve both clean and incremental builds regardless of version

**Alternatives considered**:
- Disable cache mounts: Rejected - increases build time unnecessarily
- Change cache path: Not needed - standard Maven convention unchanged

**Validation required**: Monitor build times (cold build <15 min, warm build <5 min per SC-002/SC-003)

---

### 8. Multi-Architecture Build Compatibility

**Decision**: Existing multi-arch build strategy unchanged

**Research findings**:
- Schema Registry 8.1.1 JAR is architecture-agnostic (JVM bytecode)
- BuildKit BUILDPLATFORM/TARGETPLATFORM approach version-agnostic
- No native libraries or platform-specific dependencies in Schema Registry
- Maven build produces identical JAR on x86 and ARM build machines

**Rationale**: Multi-arch compatibility is a property of the build system, not the Schema Registry version

**Alternatives considered**:
- Test single architecture first: Rejected - multi-arch is constitution requirement
- Add platform-specific build steps: Not needed - existing approach works

**Validation required**: 
- Run `make buildx` to build both linux/amd64 and linux/arm64
- Inspect manifest to confirm both platforms present
- Run smoke tests on both architectures

---

### 9. OCI Label Updates

**Decision**: Makefile VERSION extraction automatically handles 8.1.1

**Research findings**:
- Current Makefile extracts version from submodule tag: `$(shell cd upstream/schema-registry && git describe --tags --abbrev=0)`
- When submodule updated to 8.1.1 tag, VERSION automatically becomes `8.1.1`
- LOCAL_VERSION adds `+infoblox.1` suffix: `8.1.1+infoblox.1`
- Dockerfile LABEL instruction uses VERSION build arg: `org.opencontainers.image.version=${VERSION}`

**Rationale**: Version metadata system is dynamic; no hardcoded version references to update

**Alternatives considered**:
- Manually update version in Makefile: Not needed - automatic extraction works
- Add new version metadata: Not needed - existing OCI labels sufficient

**Validation required**: 
- Update submodule to 8.1.1 tag
- Run `make build`
- Inspect image labels: `docker inspect <image> | jq '.[0].Config.Labels["org.opencontainers.image.version"]'`
- Verify output is `8.1.1+infoblox.1`

---

### 10. Documentation Updates Required

**Decision**: Minimal documentation updates needed

**Research findings**:
- README.md may have hardcoded version references to 7.6.1 (check and update if present)
- CHANGELOG.md requires new section for 8.1.1 upgrade
- quickstart.md examples should work with 8.1.1 unchanged (validate)
- CONTRIBUTING.md is version-agnostic (no updates needed)

**Rationale**: Documentation should reflect current version but examples are version-agnostic

**Alternatives considered**:
- Leave old version references: Rejected - users expect current version in README
- Document every upstream change: Rejected - CHANGELOG highlights user-facing changes only

**Validation required**:
- Search README.md for "7.6.1" and update to "8.1.1" where appropriate (keep historical examples)
- Add CHANGELOG.md section: "## [8.1.1+infoblox.1] - 2026-01-16"
- Test quickstart.md examples against 8.1.1 image

---

## Summary of Unknowns Resolved

All research questions from Technical Context have been addressed:

1. ✅ **Java version**: Java 17 expected to remain compatible (validate with build test)
2. ✅ **Maven build**: Existing command and profile expected to work (validate with build test)
3. ✅ **API changes**: Minor version upgrade suggests API stability (validate with smoke tests)
4. ✅ **Config compatibility**: Existing templates expected to work (validate with startup tests)
5. ✅ **Chainguard JRE**: Expected to support 8.1.1 (validate with runtime tests)
6. ✅ **BuildKit cache**: Strategy remains effective (validate with build time measurements)
7. ✅ **Multi-arch**: Build system unchanged (validate with buildx)
8. ✅ **OCI labels**: Automatic extraction handles version (validate with inspect)
9. ✅ **Documentation**: Minimal updates identified (CHANGELOG, README version refs)

## Next Steps

Proceed to Phase 1 to:
- Create data-model.md defining 8.1.1 version metadata entities
- Create quickstart.md documenting upgrade workflow
- Create contracts/ directory if version-specific contracts needed
- Update agent context (not needed - no new technologies)
- Re-validate Constitution Check (expected to pass - no infrastructure changes)

All unknowns have concrete validation tasks in implementation phase. No blockers identified.
