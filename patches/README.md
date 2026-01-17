# Schema Registry Patches

This directory contains patches applied to the upstream Confluent Schema Registry.

## Patches

### 001-security-dependency-versions.patch
**Purpose**: Override dependency versions to mitigate CVEs  
**Affects**: `pom.xml`  
**Changes**:
- Jersey: 3.1.9 → 3.1.10 (CVE mitigation)
- Netty: 4.1.128.Final → 4.1.115.Final (CVE mitigation)
- Log4j: 2.24.3 → 2.25.3 (CVE mitigation)

## Managing Patches

### Creating a New Patch
```bash
# Make changes to files in upstream/schema-registry/
cd upstream/schema-registry
# ... edit files ...

# Generate patch
git diff > ../../patches/00X-description.patch
```

### Updating Existing Patch
```bash
# Reset the submodule
cd upstream/schema-registry
git reset --hard HEAD

# Make your changes
# ... edit files ...

# Regenerate patch
git diff > ../../patches/001-security-dependency-versions.patch
```

### Upgrading Upstream Version
```bash
# Update submodule to new version
cd upstream/schema-registry
git fetch
git checkout v8.2.0  # or desired version

# Try applying patches
for patch in ../../patches/*.patch; do
    git apply --check "$patch" || echo "CONFLICT: $patch"
done

# If conflicts, manually resolve and regenerate patches
git apply ../../patches/001-security-dependency-versions.patch
# ... resolve conflicts ...
git diff > ../../patches/001-security-dependency-versions.patch

# Update parent repo
cd ../..
git add upstream/schema-registry patches/
git commit -m "upgrade: Schema Registry 8.2.0"
```

## Testing Patches

Patches are automatically applied during Docker build. To test:
```bash
make clean
make build
```

Build will fail if patches don't apply cleanly.
