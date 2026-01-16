# Data Model: Upgrade to Schema Registry 8.1.1

**Phase**: 1 (Design)  
**Date**: 2026-01-16  
**Purpose**: Define entities and their relationships for version upgrade

## Overview

This upgrade modifies metadata entities from feature 001 without changing the build system architecture. The primary change is updating version references from 7.6.1 to 8.1.1 in version metadata, submodule pointers, and OCI labels.

## Entities

### 1. Upstream Submodule Reference (UPDATED)

**Description**: Git pointer to upstream Confluent Schema Registry repository, updated to 8.1.1 release tag.

**Attributes**:
- `repository_url`: String - `https://github.com/confluentinc/schema-registry` (unchanged)
- `submodule_path`: String - `upstream/schema-registry` (unchanged)
- `commit_sha`: String - SHA of commit tagged as `8.1.1` in upstream (CHANGED from 7.6.1 commit)
- `tag`: String - `8.1.1` (CHANGED from `7.6.1`)
- `branch`: String - Not used (pin to tag for reproducibility)

**Relationships**:
- Referenced by BuildConfiguration for Maven build source
- Determines version in VersionMetadata entity
- Compiled into BuildArtifact (8.1.1 JAR)

**Lifecycle**:
1. **Updated**: `cd upstream/schema-registry && git fetch --tags && git checkout 8.1.1`
2. **Committed**: `git add upstream/schema-registry && git commit -m "Update to Schema Registry 8.1.1"`
3. **Validated**: Pre-build check ensures submodule points to valid 8.1.1 tag
4. **Built**: Maven executes within updated submodule directory

**Changes from 7.6.1**:
- `commit_sha`: Updated to 8.1.1 tag commit
- `tag`: `7.6.1` → `8.1.1`

---

### 2. Version Metadata (UPDATED)

**Description**: Composite version string combining upstream Schema Registry version with local build iteration.

**Attributes**:
- `upstream_version`: String - `8.1.1` (CHANGED from `7.6.1`)
- `local_suffix`: String - `+infoblox.1` (RESET to `.1` for new upstream version)
- `full_version`: String - `8.1.1+infoblox.1` (computed: upstream_version + local_suffix)
- `extraction_method`: String - `git describe --tags --abbrev=0` in submodule directory (unchanged)
- `format`: String - Semantic versioning with build metadata (unchanged)

**Relationships**:
- Derived from UpstreamSubmoduleReference tag
- Embedded in OCILabels (org.opencontainers.image.version)
- Displayed in Makefile info target output

**Lifecycle**:
1. **Extracted**: Makefile runs `cd upstream/schema-registry && git describe --tags --abbrev=0` → returns `8.1.1`
2. **Suffixed**: Makefile appends `+infoblox.1` → produces `8.1.1+infoblox.1`
3. **Passed**: Build arg `VERSION=8.1.1+infoblox.1` passed to Docker build
4. **Labeled**: Dockerfile LABEL instruction embeds version in image metadata

**Changes from 7.6.1**:
- `upstream_version`: `7.6.1` → `8.1.1`
- `full_version`: `7.6.1+infoblox.1` → `8.1.1+infoblox.1`

**Iteration Logic**:
- First build of 8.1.1: `8.1.1+infoblox.1`
- Subsequent builds (e.g., config changes only): `8.1.1+infoblox.2`, `8.1.1+infoblox.3`, etc.

---

### 3. Build Artifact (UPDATED)

**Description**: Schema Registry standalone JAR produced by Maven, now version 8.1.1.

**Attributes**:
- `source_path`: String - `package-schema-registry/target/kafka-schema-registry-package-8.1.1-standalone.jar` (CHANGED version in filename)
- `destination_path`: String - `/app/schema-registry.jar` (unchanged - generic name in image)
- `size_mb`: Integer - ~150-200 MB typical (unchanged - similar size expected)
- `format`: String - JAR (Java Archive) (unchanged)
- `dependencies_bundled`: Boolean - True (standalone = fat JAR) (unchanged)
- `architecture_agnostic`: Boolean - True (JVM bytecode) (unchanged)

**Relationships**:
- Produced by BuildConfiguration (Maven 3.x + Java 17 + 8.1.1 source)
- Sourced from UpstreamSubmoduleReference (8.1.1 codebase)
- Packaged into ContainerImage (8.1.1 runtime)

**Validation**:
- Must exist after Maven build with 8.1.1 version in filename
- Must be executable JAR with valid manifest
- Must contain `kafka-schema-registry` main class

**Changes from 7.6.1**:
- `source_path`: `*-7.6.1-standalone.jar` → `*-8.1.1-standalone.jar` (glob pattern in Dockerfile handles automatically)

---

### 4. OCI Labels (UPDATED)

**Description**: Metadata annotations attached to container image per OCI Image Specification, now reflecting 8.1.1.

**Attributes**:
- `org.opencontainers.image.source`: String - Repository URL (unchanged)
- `org.opencontainers.image.version`: String - `8.1.1+infoblox.1` (CHANGED from `7.6.1+infoblox.1`)
- `org.opencontainers.image.revision`: String - Git commit SHA of this repo (changed - new commit for upgrade)
- `org.opencontainers.image.created`: String - RFC 3339 build timestamp (changed - new build time)
- `org.opencontainers.image.title`: String - "Infoblox Schema Registry" (unchanged)
- `org.opencontainers.image.description`: String - Description text (unchanged)
- `org.opencontainers.image.vendor`: String - "Infoblox" (unchanged)

**Relationships**:
- Receives version from VersionMetadata entity
- Receives revision from git repository of this project
- Embedded in ContainerImage metadata

**Lifecycle**:
1. **Computed**: Makefile extracts VERSION and VCS_REF
2. **Passed**: Build args passed to Dockerfile
3. **Labeled**: Dockerfile LABEL instructions set OCI annotations
4. **Inspectable**: Users query with `docker inspect` or `docker buildx imagetools inspect`

**Changes from 7.6.1**:
- `version`: `7.6.1+infoblox.1` → `8.1.1+infoblox.1`
- `revision`: Updated to commit SHA of upgrade PR
- `created`: Updated to build timestamp of 8.1.1 image

---

### 5. Container Image (UPDATED VERSION ONLY)

**Description**: Multi-architecture OCI container image, now containing Schema Registry 8.1.1.

**Attributes** (changes only):
- `tag`: String - Updated tags: `8.1.1+infoblox.1`, `8.1.1`, `latest`
- `labels`: Map[String, String] - OCI annotations with 8.1.1 version (see OCILabels entity)

**Attributes** (unchanged):
- `registry`: String - `ghcr.io` (or user-specified)
- `repository`: String - `infobloxopen/ib-schema-registry`
- `platforms`: Array[String] - `["linux/amd64", "linux/arm64"]`
- `layers`: Array[Layer] - Image filesystem layers (builder artifacts, runtime files, config)
- `entrypoint`: Array[String] - `["java", "-jar", "/app/schema-registry.jar"]`
- `cmd`: Array[String] - `["/etc/schema-registry/schema-registry.properties"]`
- `user`: Integer - 65532
- `workdir`: String - `/app`
- `exposed_ports`: Array[Integer] - [8081]

**Relationships**:
- Built from UpstreamSubmoduleReference (8.1.1 source)
- Contains BuildArtifact (8.1.1 JAR)
- Includes RuntimeConfiguration (unchanged config template)
- Described by OCILabels (8.1.1 metadata)

**Changes from 7.6.1**:
- Runtime artifact version: 7.6.1 JAR → 8.1.1 JAR
- Image tags: `7.6.1+infoblox.1` → `8.1.1+infoblox.1`
- Metadata labels: version field updated

---

### 6. Runtime Configuration (UNCHANGED)

**Description**: Schema Registry properties file defining runtime behavior - expected to remain compatible.

**Attributes** (all unchanged):
- `file_path`: String - `/etc/schema-registry/schema-registry.properties`
- `listeners`: String - `http://0.0.0.0:8081`
- `kafkastore_bootstrap_servers`: String - `PLAINTEXT://kafka:9092`
- `kafkastore_topic`: String - `_schemas`
- `schema_compatibility_level`: String - `BACKWARD`
- `format`: String - Java properties file

**Relationships**:
- Packaged into ContainerImage (unchanged)
- Consumed by Schema Registry 8.1.1 at runtime (validated for compatibility)
- Can be overridden by user volume mount

**Validation**:
- Start 8.1.1 container with existing config
- Check logs for deprecation warnings
- Document any new recommended properties in CHANGELOG

**Changes from 7.6.1**: None expected (validate during testing)

---

### 7. Build Configuration (UNCHANGED)

**Description**: Makefile variables and Docker build arguments - remain identical.

**Attributes** (all unchanged except extracted values):
- `IMAGE`: String - Full image name (default: `ghcr.io/infobloxopen/ib-schema-registry`)
- `TAG`: String - Image tag (default: `dev`)
- `PLATFORMS`: String - `linux/amd64,linux/arm64`
- `BUILDER_IMAGE`: String - `maven:3-eclipse-temurin-17` (unchanged if Java 17 compatible)
- `RUNTIME_IMAGE`: String - `cgr.dev/chainguard/jre:latest` (unchanged)
- `APP_UID`: Integer - 65532 (unchanged)
- `VERSION`: String - Extracted from submodule → `8.1.1+infoblox.1` (computed, not hardcoded)
- `BUILD_DATE`: String - RFC 3339 timestamp (computed at build time)
- `VCS_REF`: String - Git commit SHA of this repo (computed from HEAD)

**Changes from 7.6.1**:
- `VERSION` extraction returns `8.1.1` instead of `7.6.1` (automatic from submodule tag)

---

## Entity Relationship Diagram (Conceptual)

```
UpstreamSubmoduleReference (8.1.1 tag)
  ↓
  ├─→ VersionMetadata (8.1.1+infoblox.1)
  │     ↓
  │     └─→ OCILabels (version: 8.1.1+infoblox.1)
  │           ↓
  │           └─→ ContainerImage (tagged: 8.1.1+infoblox.1)
  │
  └─→ BuildConfiguration (Maven build with 8.1.1 source)
        ↓
        └─→ BuildArtifact (8.1.1 standalone JAR)
              ↓
              └─→ ContainerImage (contains 8.1.1 runtime)
```

## Changes Summary

| Entity | Changes from 7.6.1 | Impact |
|--------|-------------------|---------|
| UpstreamSubmoduleReference | `tag`: 7.6.1 → 8.1.1<br>`commit_sha`: Updated | Drives all downstream version changes |
| VersionMetadata | `upstream_version`: 7.6.1 → 8.1.1<br>`full_version`: 7.6.1+infoblox.1 → 8.1.1+infoblox.1 | Automatic extraction from submodule |
| BuildArtifact | `source_path`: *-7.6.1-*.jar → *-8.1.1-*.jar | Glob pattern handles automatically |
| OCILabels | `version`: 7.6.1+infoblox.1 → 8.1.1+infoblox.1<br>`revision`: Updated commit SHA<br>`created`: New timestamp | Metadata reflects new version |
| ContainerImage | `tag`: 7.6.1+infoblox.1 → 8.1.1+infoblox.1<br>Runtime JAR version updated | User-facing artifact version |
| RuntimeConfiguration | None (validated for compatibility) | Backward compatibility expected |
| BuildConfiguration | `VERSION` computed value changes | No hardcoded changes needed |

## Validation Checklist

- [ ] Submodule points to 8.1.1 tag: `git submodule status`
- [ ] Version extraction returns `8.1.1`: `cd upstream/schema-registry && git describe --tags --abbrev=0`
- [ ] Build artifact has 8.1.1 in filename: Check Maven target directory
- [ ] OCI label shows `8.1.1+infoblox.1`: `docker inspect <image> | jq '.[0].Config.Labels["org.opencontainers.image.version"]'`
- [ ] Container starts with 8.1.1 runtime: Check logs for Schema Registry version output
- [ ] Existing config works: No errors/warnings when starting with default config

All entity changes are driven by the submodule update; build system handles version propagation automatically.
