# Quickstart: Upgrading to Schema Registry 8.1.1

**Purpose**: Step-by-step guide for upgrading from 7.6.1 to 8.1.1

**Audience**: Maintainers performing version upgrades

## Prerequisites

- Existing repository with Schema Registry 7.6.1 (from feature 001)
- Git with submodule support
- Docker with BuildKit enabled
- Make (for ergonomic targets)
- Clean working directory (no uncommitted changes)

## Upgrade Workflow

### Step 1: Update Upstream Submodule

```bash
# Navigate to repository root
cd /path/to/ib-schema-registry

# Fetch latest tags from upstream
cd upstream/schema-registry
git fetch --tags origin

# Verify 8.1.1 tag exists
git tag | grep ^8.1.1$
# Expected output: 8.1.1

# Checkout 8.1.1 tag
git checkout 8.1.1

# Return to repo root
cd ../..

# Stage submodule update
git add upstream/schema-registry

# Verify submodule status
git submodule status upstream/schema-registry
# Expected: +<commit-sha> upstream/schema-registry (8.1.1)
```

**Validation**: Submodule pointer now references 8.1.1 tag commit

---

### Step 2: Verify Version Extraction

```bash
# Test Makefile version extraction
make info

# Expected output includes:
# VERSION=8.1.1+infoblox.1
# (or similar, confirming 8.1.1 detected)
```

**Validation**: Makefile correctly extracts 8.1.1 from submodule tag

---

### Step 3: Clean Build Environment

```bash
# Remove old images and build cache (optional but recommended)
make clean

# Or manually:
docker rmi ib-schema-registry:dev 2>/dev/null || true
docker builder prune -f
```

**Rationale**: Ensures build uses fresh 8.1.1 source without 7.6.1 artifacts

---

### Step 4: Build for Native Platform

```bash
# Build 8.1.1 image for your native architecture
make build

# Monitor build output for:
# - Maven download of 8.1.1 dependencies
# - Successful package of kafka-schema-registry-package-8.1.1-standalone.jar
# - Image tagged as ib-schema-registry:dev
```

**Expected build time**:
- Cold build (first time): 12-15 minutes (Maven downloads dependencies)
- Warm build (cache hit): 3-5 minutes

**Validation**: Build completes without errors; image is created

---

### Step 5: Verify OCI Labels

```bash
# Inspect image metadata
docker inspect ib-schema-registry:dev | jq '.[0].Config.Labels'

# Check specific version label
docker inspect ib-schema-registry:dev | \
  jq -r '.[0].Config.Labels["org.opencontainers.image.version"]'

# Expected output: 8.1.1+infoblox.1
```

**Validation**: OCI version label reflects 8.1.1

---

### Step 6: Run Smoke Tests

```bash
# Execute smoke test suite
make test

# Expected output:
# - Container starts successfully
# - Schema Registry initialization completes
# - GET /subjects returns []
# - Test exits with code 0
```

**Validation**: 8.1.1 container passes all smoke tests

---

### Step 7: Test Configuration Compatibility

```bash
# Test with default config
docker run --rm -p 8081:8081 \
  -e JAVA_TOOL_OPTIONS="-Xms256m -Xmx512m" \
  ib-schema-registry:dev &

# Wait for startup (check logs)
sleep 10

# Verify API responds
curl http://localhost:8081/subjects
# Expected: []

# Check logs for deprecation warnings
docker logs $(docker ps -q -f ancestor=ib-schema-registry:dev) 2>&1 | \
  grep -i "deprecat"

# Stop container
docker stop $(docker ps -q -f ancestor=ib-schema-registry:dev)
```

**Validation**: 
- Container starts with existing config
- No errors or unexpected warnings
- API endpoints respond correctly

---

### Step 8: Test Base Image Compatibility

#### Test Chainguard JRE (Default)

```bash
# Build with Chainguard default (should already be built in Step 4)
# Verify distroless (no shell)
docker run --rm ib-schema-registry:dev /bin/sh -c "echo test"
# Expected: Error - executable file not found (distroless confirmed)
```

#### Test Temurin Fallback

```bash
# Build with Temurin override
make build RUNTIME_IMAGE=eclipse-temurin:17-jre TAG=8.1.1-temurin

# Run smoke tests on Temurin variant
docker run --rm -p 8082:8081 \
  ib-schema-registry:8.1.1-temurin &

sleep 10
curl http://localhost:8082/subjects
# Expected: []

docker stop $(docker ps -q -f ancestor=ib-schema-registry:8.1.1-temurin)
```

**Validation**: Both Chainguard and Temurin runtimes work with 8.1.1

---

### Step 9: Multi-Architecture Build

```bash
# Build for both amd64 and arm64
make buildx

# Inspect multi-arch manifest
docker buildx imagetools inspect ib-schema-registry:dev

# Expected output shows both platforms:
# - linux/amd64
# - linux/arm64
```

**Validation**: Both architectures build successfully

---

### Step 10: Update Documentation

#### Update CHANGELOG.md

```bash
# Edit CHANGELOG.md - add new section at top:
cat >> CHANGELOG.md << 'EOF'

## [8.1.1+infoblox.1] - 2026-01-16

### Changed

- Upgraded upstream Confluent Schema Registry from 7.6.1 to 8.1.1
- Updated git submodule to point to upstream 8.1.1 tag

### Validated

- ✅ Maven build succeeds with Java 17
- ✅ Multi-architecture builds (linux/amd64 + linux/arm64) complete successfully
- ✅ Chainguard JRE (default runtime) compatible with 8.1.1
- ✅ Eclipse Temurin fallback (override) compatible with 8.1.1
- ✅ Existing configuration files work without modification
- ✅ Smoke tests pass on both architectures
- ✅ OCI labels reflect 8.1.1+infoblox.1 version

### Breaking Changes

[Add any breaking changes discovered during testing - to be filled during implementation]

### Known Issues

[Add any known issues discovered during testing - to be filled during implementation]

EOF
```

#### Update README.md (if version references exist)

```bash
# Search for hardcoded version references
grep -n "7\.6\.1" README.md

# Update to 8.1.1 where appropriate (e.g., examples, current version)
# Keep 7.6.1 in historical examples or upgrade documentation
sed -i.bak 's/7\.6\.1/8.1.1/g' README.md

# Review changes
git diff README.md

# Restore if over-aggressive
# mv README.md.bak README.md
```

**Validation**: Documentation reflects 8.1.1 as current version

---

### Step 11: Commit Changes

```bash
# Review all changes
git status
git diff

# Stage changes
git add upstream/schema-registry CHANGELOG.md README.md

# Commit with descriptive message
git commit -m "feat: upgrade Schema Registry to 8.1.1

- Update upstream submodule from 7.6.1 to 8.1.1 tag
- Validate Maven build compatibility with Java 17
- Confirm multi-arch builds (amd64 + arm64) successful
- Verify Chainguard JRE and Temurin fallback compatibility
- Test existing configuration files (no changes needed)
- Update documentation (CHANGELOG, README)

All smoke tests pass. No breaking changes identified.

Closes #002-upgrade-8-1-1"
```

**Validation**: Clean commit with submodule update and documentation

---

### Step 12: Tag Release (Optional)

```bash
# Tag the release
git tag -a v8.1.1+infoblox.1 -m "Schema Registry 8.1.1 (Infoblox build 1)"

# Push to remote
git push origin HEAD
git push origin v8.1.1+infoblox.1
```

---

## Validation Checklist

After completing the upgrade, verify:

- [ ] Submodule points to 8.1.1 tag: `git submodule status`
- [ ] Makefile extracts version 8.1.1: `make info | grep VERSION`
- [ ] Build succeeds: `make build` exits 0
- [ ] OCI label correct: `docker inspect` shows `8.1.1+infoblox.1`
- [ ] Smoke tests pass: `make test` exits 0
- [ ] Config compatibility: Container starts with existing config/schema-registry.properties
- [ ] Chainguard works: Build with default RUNTIME_IMAGE, smoke tests pass
- [ ] Temurin works: Build with `RUNTIME_IMAGE=eclipse-temurin:17-jre`, smoke tests pass
- [ ] Multi-arch builds: `make buildx` succeeds, manifest has both platforms
- [ ] CHANGELOG updated: New section for 8.1.1+infoblox.1
- [ ] README updated: Version references current (if applicable)
- [ ] Commit clean: `git status` shows committed changes

## Troubleshooting

### Build Fails with Maven Errors

**Symptom**: Maven build fails during Docker build

**Possible causes**:
- Java version incompatibility (8.1.1 requires Java 21?)
- Maven profile changes (standalone profile renamed?)
- Network issues (Maven Central unreachable)

**Solutions**:
1. Check upstream release notes for Java version requirement
2. If Java 21 required: Update BUILDER_IMAGE to `maven:3-eclipse-temurin-21`
3. Test Maven build locally in submodule: `cd upstream/schema-registry && mvn clean package -DskipTests -P standalone`
4. Check build logs for specific error messages

---

### Container Fails to Start

**Symptom**: `make test` fails, container exits immediately

**Possible causes**:
- Configuration syntax changes in 8.1.1
- JAR file not properly copied into image
- Runtime image incompatibility

**Solutions**:
1. Check container logs: `docker logs <container-id>`
2. Verify JAR exists: `docker run --rm --entrypoint ls ib-schema-registry:dev /app`
3. Test with minimal config: Remove all custom properties, use only listeners and kafkastore.bootstrap.servers
4. Test with Temurin override: `make build RUNTIME_IMAGE=eclipse-temurin:17-jre` to isolate Chainguard issues

---

### OCI Label Shows Wrong Version

**Symptom**: `docker inspect` shows version other than 8.1.1+infoblox.1

**Possible causes**:
- Makefile VERSION extraction failed
- Submodule not properly updated
- Cached image from old build

**Solutions**:
1. Verify submodule: `cd upstream/schema-registry && git describe --tags --abbrev=0` should return `8.1.1`
2. Clean build: `make clean && make build`
3. Manually pass VERSION: `make build VERSION=8.1.1+infoblox.1`

---

### Configuration Warnings in Logs

**Symptom**: Container starts but logs show deprecation warnings

**Resolution**:
- Document warnings in CHANGELOG.md under "Deprecation Notices"
- Update config/examples/ files with new recommended properties
- Link to upstream documentation for new config options
- Old properties typically still work (backward compatibility)

---

## Rollback Procedure

If 8.1.1 upgrade fails and cannot be resolved:

```bash
# Revert submodule to 7.6.1
cd upstream/schema-registry
git checkout 7.6.1
cd ../..

# Stage revert
git add upstream/schema-registry

# Commit revert
git commit -m "revert: rollback to Schema Registry 7.6.1

8.1.1 upgrade encountered issues:
[Describe specific issues encountered]

Reverting to stable 7.6.1 until issues resolved."

# Rebuild 7.6.1
make clean
make build
make test
```

## Next Steps

After successful upgrade:

1. **Push to registry**: `make push IMAGE=ghcr.io/infobloxopen/ib-schema-registry TAG=8.1.1+infoblox.1`
2. **Update CI/CD**: Verify GitHub Actions workflow builds 8.1.1 successfully
3. **Test in staging**: Deploy 8.1.1 image to staging environment
4. **Monitor production**: Gradual rollout to production clusters
5. **Document learnings**: Add any discovered issues or tips to CONTRIBUTING.md

## Reference Links

- Upstream release notes: https://docs.confluent.io/platform/current/release-notes/
- Schema Registry docs: https://docs.confluent.io/platform/current/schema-registry/
- Feature 001 original implementation: [../001-schema-registry-image/](../001-schema-registry-image/)
- Constitution compliance: [../../.specify/memory/constitution.md](../../.specify/memory/constitution.md)
