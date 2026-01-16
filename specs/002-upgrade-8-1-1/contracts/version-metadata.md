# Contract: Version Metadata for 8.1.1

**Purpose**: Define the version metadata format and OCI label requirements for Schema Registry 8.1.1 upgrade

**Applies to**: Container images, OCI labels, Makefile version extraction

## Version Format Contract

### Composite Version String

**Format**: `<UPSTREAM_VERSION>+infoblox.<ITERATION>`

**Components**:
- `UPSTREAM_VERSION`: Confluent Schema Registry version from git tag (e.g., `8.1.1`)
- `+`: Build metadata separator per [Semantic Versioning 2.0.0](https://semver.org/)
- `infoblox`: Build identifier indicating Infoblox-maintained build
- `ITERATION`: Sequential build number for this upstream version (starts at `1`)

**Examples**:
- First build of 8.1.1: `8.1.1+infoblox.1`
- Second build (e.g., config update): `8.1.1+infoblox.2`
- Third build: `8.1.1+infoblox.3`

**Extraction Method**:
```makefile
# Makefile automatic extraction
VERSION := $(shell cd upstream/schema-registry && git describe --tags --abbrev=0)
LOCAL_VERSION := $(VERSION)+infoblox.1
```

---

## OCI Label Requirements

### Required Labels (OCI Image Spec)

All images MUST include the following labels as per [OCI Image Spec Annotations](https://github.com/opencontainers/image-spec/blob/main/annotations.md):

#### org.opencontainers.image.version

**Value**: `8.1.1+infoblox.1`  
**Format**: Composite version string (see above)  
**Source**: Makefile VERSION variable  
**Validation**: Must match pattern `^\d+\.\d+\.\d+\+infoblox\.\d+$`

**Example**:
```dockerfile
LABEL org.opencontainers.image.version="${VERSION}"
```

**Verification**:
```bash
docker inspect ib-schema-registry:dev | \
  jq -r '.[0].Config.Labels["org.opencontainers.image.version"]'
# Expected output: 8.1.1+infoblox.1
```

---

#### org.opencontainers.image.source

**Value**: `https://github.com/infobloxopen/ib-schema-registry`  
**Format**: Full repository URL  
**Source**: Hardcoded in Dockerfile (unchanged from 7.6.1)  
**Purpose**: Link to build tooling repository (not upstream Confluent repo)

**Example**:
```dockerfile
LABEL org.opencontainers.image.source="https://github.com/infobloxopen/ib-schema-registry"
```

---

#### org.opencontainers.image.revision

**Value**: Git commit SHA of this repository (HEAD at build time)  
**Format**: 40-character hex string  
**Source**: `git rev-parse HEAD` in Makefile  
**Purpose**: Traceability to exact build tooling version

**Example**:
```dockerfile
LABEL org.opencontainers.image.revision="${VCS_REF}"
```

**Makefile**:
```makefile
VCS_REF := $(shell git rev-parse HEAD)
```

---

#### org.opencontainers.image.created

**Value**: RFC 3339 timestamp of build  
**Format**: `YYYY-MM-DDTHH:MM:SSZ`  
**Source**: `date -u +"%Y-%m-%dT%H:%M:%SZ"` in Makefile  
**Purpose**: Build reproducibility and freshness tracking

**Example**:
```dockerfile
LABEL org.opencontainers.image.created="${BUILD_DATE}"
```

**Makefile**:
```makefile
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
```

---

#### org.opencontainers.image.title

**Value**: `Infoblox Schema Registry`  
**Format**: Human-readable title  
**Source**: Hardcoded in Dockerfile (unchanged from 7.6.1)

---

#### org.opencontainers.image.description

**Value**: `Multi-architecture Confluent Schema Registry built from source`  
**Format**: Brief description  
**Source**: Hardcoded in Dockerfile (unchanged from 7.6.1)

---

#### org.opencontainers.image.vendor

**Value**: `Infoblox`  
**Format**: Organization name  
**Source**: Hardcoded in Dockerfile (unchanged from 7.6.1)

---

## Image Tag Contract

### Tag Format

**Primary tag**: `<VERSION>` (e.g., `8.1.1+infoblox.1`)  
**Short tag**: `<UPSTREAM_VERSION>` (e.g., `8.1.1`)  
**Latest tag**: `latest` (points to most recent stable build)

**Multi-arch manifest**: All tags MUST be multi-arch manifests containing both `linux/amd64` and `linux/arm64` images

**Examples**:
```bash
# Full version with iteration
ib-schema-registry:8.1.1+infoblox.1

# Short version (alias to latest iteration)
ib-schema-registry:8.1.1

# Latest (alias to most recent stable)
ib-schema-registry:latest

# Development build
ib-schema-registry:dev
```

---

## Version Transition Contract

### Upgrading from 7.6.1 to 8.1.1

**Iteration reset**: When upstream version changes, iteration resets to `1`

**Examples**:
- Last 7.6.1 build: `7.6.1+infoblox.3`
- First 8.1.1 build: `8.1.1+infoblox.1` (NOT `8.1.1+infoblox.4`)

**Rationale**: Iteration tracks builds for specific upstream version, not global build count

---

### Incrementing Iteration

**When to increment**: Configuration changes, documentation updates, build tooling updates that don't change upstream version

**Examples**:
- Build 1: `8.1.1+infoblox.1` - Initial 8.1.1 upgrade
- Build 2: `8.1.1+infoblox.2` - Updated config/examples/production.properties
- Build 3: `8.1.1+infoblox.3` - Fixed Makefile bug

**Manual override** (if automatic extraction fails):
```bash
make build VERSION=8.1.1+infoblox.2
```

---

## Validation Contract

### Build-time Validation

The build process MUST validate version metadata before completion:

**Checks**:
1. ✅ Submodule tag exists: `git tag -l 8.1.1` in submodule returns result
2. ✅ Version extraction succeeds: `git describe --tags --abbrev=0` returns `8.1.1`
3. ✅ JAR version matches: Maven build produces `*-8.1.1-standalone.jar`
4. ✅ OCI label present: `docker inspect` shows `org.opencontainers.image.version`
5. ✅ Label format valid: Version matches regex `^\d+\.\d+\.\d+\+infoblox\.\d+$`

---

### Runtime Validation

**API version check** (if exposed):
```bash
curl http://localhost:8081/ | jq -r '.version'
# Expected: 8.1.1 (upstream version from Schema Registry runtime)
```

**Container logs** (startup verification):
```bash
docker logs <container> 2>&1 | grep -i "version"
# Expected: Log line showing Schema Registry 8.1.1 started
```

---

## Compliance with Feature 001

This contract maintains compatibility with feature 001's version metadata design:

- ✅ Same version format (`<VERSION>+infoblox.<N>`)
- ✅ Same OCI labels (all 7 required annotations)
- ✅ Same extraction method (Makefile `git describe --tags`)
- ✅ Same image tag strategy (full version + short version + latest)

**Only change**: Upstream version component (`7.6.1` → `8.1.1`)

---

## Non-Functional Requirements

### Version Immutability

Once a version tag is pushed to registry (e.g., `8.1.1+infoblox.1`), it MUST NOT be overwritten.

**Enforcement**:
- Use `docker push` without `--force` flag
- Registry policies prevent tag overwrites (if supported)
- GitHub Actions workflow validates tag uniqueness before push

**Rationale**: Ensures reproducibility and prevents confusion from changing artifacts

---

### Version Discoverability

Users MUST be able to discover available versions:

**Via registry**:
```bash
docker pull ghcr.io/infobloxopen/ib-schema-registry:8.1.1+infoblox.1
```

**Via OCI labels**:
```bash
docker inspect ghcr.io/infobloxopen/ib-schema-registry:latest | \
  jq -r '.[0].Config.Labels["org.opencontainers.image.version"]'
```

**Via CHANGELOG.md**:
```markdown
## [8.1.1+infoblox.1] - 2026-01-16
```

---

## Contract Violations

The following are NOT permitted:

- ❌ Version mismatch: JAR is 8.1.1 but OCI label shows 7.6.1
- ❌ Missing iteration: Version shows `8.1.1` without `+infoblox.<N>` suffix
- ❌ Wrong label key: Using custom label instead of OCI standard `org.opencontainers.image.version`
- ❌ Hardcoded version: Dockerfile contains `LABEL version="8.1.1"` instead of `LABEL version="${VERSION}"`
- ❌ Tag overwrite: Pushing `8.1.1+infoblox.1` twice with different content

**Enforcement**: CI validation fails build if labels missing or malformed

---

## References

- [Semantic Versioning 2.0.0](https://semver.org/)
- [OCI Image Spec Annotations](https://github.com/opencontainers/image-spec/blob/main/annotations.md)
- Feature 001 OCI labels contract: [../001-schema-registry-image/contracts/oci-labels.md](../../001-schema-registry-image/contracts/oci-labels.md)
