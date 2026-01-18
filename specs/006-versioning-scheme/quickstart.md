# Quickstart: Testing Unified Versioning Scheme

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Quick Test Commands

### Check Current Version
```bash
# From repository root
make version

# Or directly call script
./scripts/version.sh
```

**Expected output format**:
- Main branch: `8.1.1-ib.main.abc1234`
- Feature branch: `8.1.1-ib.feature-name.abc1234`
- Release tag: `8.1.1-ib.1.abc1234`
- Dirty build: `8.1.1-ib.main.abc1234.dirty`

### Test Version Components
```bash
# Get just the upstream version
./scripts/version.sh --upstream-only
# Expected: 8.1.1

# Get version as JSON
./scripts/version.sh --format=json
# Expected: {"TAG":"8.1.1-ib.main.abc1234","UPSTREAM_VERSION":"8.1.1","SHA":"abc1234","DIRTY":"false"}

# Get version as GitHub Actions output format
./scripts/version.sh --format=github
# Expected:
# TAG=8.1.1-ib.main.abc1234
# UPSTREAM_VERSION=8.1.1
# SHA=abc1234
# DIRTY=false
```

### Validate Version Format
```bash
# Validate current version
make version-validate

# Or validate specific version string
./scripts/validate-version.sh "8.1.1-ib.1.abc1234"
# Expected: ✓ Version format valid
```

### Test Scenario: Main Branch Build
```bash
# Ensure you're on main branch
git checkout main
git pull

# Check version
make version
# Expected: <upstream>-ib.main.<7-char-sha>

# Build Docker image
make build
# Image will be tagged with computed version
```

### Test Scenario: Release Tag Build
```bash
# Create test release tag
git checkout main
git tag v8.1.1-ib.1
git checkout v8.1.1-ib.1

# Check version
make version
# Expected: 8.1.1-ib.1.<7-char-sha>

# Build and verify
make build
docker images | grep ib-schema-registry
```

### Test Scenario: Feature Branch Build
```bash
# Create feature branch
git checkout -b feature/test-versioning
make version
# Expected: 8.1.1-ib.feature-test-versioning.<sha>

# Test with special characters
git checkout -b feature/add-oauth2+support
make version
# Expected: 8.1.1-ib.feature-add-oauth2-support.<sha>
# (+ converted to -)
```

### Test Scenario: Dirty Build Detection
```bash
# Make uncommitted change
echo "# Test" >> README.md

# Check version
make version
# Expected: <upstream>-ib.<branch>.<sha>.dirty

# Verify dirty detection in script
./scripts/version.sh | grep "\.dirty$"
# Should match

# Clean up
git checkout README.md
```

### Test CI Workflow Locally (with act)
```bash
# Install act if not already installed
# brew install act  # macOS
# https://github.com/nektos/act

# Test workflow with version computation
act push --job build
```

## Verification Checklist

After implementing versioning changes, verify:

- [ ] `make version` returns expected format
- [ ] Version includes 7-character SHA (not 8 or 6)
- [ ] Version includes `.dirty` only when there are uncommitted changes
- [ ] Branch names are sanitized (no `/`, `+`, or other invalid chars)
- [ ] Branch names longer than 50 chars are truncated
- [ ] Release tags extract `<n>` from tag name correctly
- [ ] Main branch uses `-ib.main.` segment
- [ ] Feature branches use `-ib.<branch>.` segment
- [ ] Version string parses as valid semver prerelease identifier
- [ ] Version string contains only `[A-Za-z0-9._-]` characters
- [ ] Docker image tags match computed version
- [ ] Helm chart version matches Docker image version
- [ ] Helm chart appVersion shows upstream version
- [ ] OCI labels include both full TAG and UPSTREAM_VERSION
- [ ] No `+` characters appear in version strings
- [ ] `make build VERSION=custom` override still works

## Common Issues & Solutions

### Issue: "upstream version not found"
```bash
# Solution: Initialize upstream submodule
git submodule update --init --recursive
cd upstream/schema-registry
git fetch --tags
```

### Issue: "git describe fails" in CI (shallow clone)
```bash
# Solution: Ensure CI fetches tags
# In .github/workflows/build-image.yml:
- uses: actions/checkout@v4
  with:
    fetch-depth: 0  # Fetch all history for git describe
    submodules: true
```

### Issue: Version contains unexpected characters
```bash
# Debug: Check raw git output
git rev-parse --abbrev-ref HEAD  # Branch name
git rev-parse --short=7 HEAD     # SHA
git status --porcelain           # Dirty status

# Solution: Verify sanitization function works
./scripts/version.sh --debug
```

### Issue: Dirty flag always present
```bash
# Check if any files are actually modified
git status

# Check if git index is corrupt
git update-index --refresh

# Solution: Clean working directory
git reset --hard HEAD
```

### Issue: Version too long for OCI tag
```bash
# Check version length
./scripts/version.sh | wc -c
# Should be < 128 chars (OCI spec allows up to 128)

# If branch name too long, it will be truncated automatically
# Branch name limited to 50 chars in sanitization
```

## Integration Test Script

Save as `test-versioning-integration.sh`:

```bash
#!/bin/bash
set -euo pipefail

echo "🧪 Testing versioning integration..."

# Test 1: Version script exists and is executable
if [[ ! -x scripts/version.sh ]]; then
  echo "❌ scripts/version.sh not found or not executable"
  exit 1
fi
echo "✅ Version script exists"

# Test 2: Version output is non-empty
VERSION=$(./scripts/version.sh)
if [[ -z "$VERSION" ]]; then
  echo "❌ Version output is empty"
  exit 1
fi
echo "✅ Version computed: $VERSION"

# Test 3: Version matches expected format
if ! echo "$VERSION" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-ib\.[a-z0-9.-]+\.[a-z0-9]{7}(\.dirty)?$'; then
  echo "❌ Version format invalid: $VERSION"
  exit 1
fi
echo "✅ Version format valid"

# Test 4: Validation script accepts version
if ! ./scripts/validate-version.sh "$VERSION"; then
  echo "❌ Version validation failed"
  exit 1
fi
echo "✅ Version validation passed"

# Test 5: Makefile version target works
MAKE_VERSION=$(make version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-ib\.[a-z0-9.-]+')
if [[ -z "$MAKE_VERSION" ]]; then
  echo "❌ make version failed"
  exit 1
fi
echo "✅ make version works: $MAKE_VERSION"

# Test 6: Docker build uses correct version
echo "🐳 Testing Docker build..."
make build TAG=test-version
if ! docker images | grep "test-version"; then
  echo "❌ Docker image not tagged correctly"
  exit 1
fi
echo "✅ Docker build successful"

# Cleanup
docker rmi ib-schema-registry:test-version 2>/dev/null || true

echo ""
echo "🎉 All integration tests passed!"
echo "Version: $VERSION"
```

Make it executable and run:
```bash
chmod +x test-versioning-integration.sh
./test-versioning-integration.sh
```

## Next Steps

After verifying version computation works locally:

1. **Create PR**: Push changes to feature branch
2. **Test CI**: Verify GitHub Actions workflow completes successfully
3. **Review artifacts**: Check Docker image tags and Helm chart versions in GHCR
4. **Test deployment**: Deploy using new version format
5. **Merge**: Merge to main after approval
6. **Create release**: Tag first release using new format (`v8.1.1-ib.1`)
7. **Monitor**: Ensure production builds use new versioning

## Documentation References

- **Specification**: [spec.md](spec.md)
- **Implementation Plan**: [plan.md](plan.md)
- **Version Format Contract**: [contracts/version-format.md](contracts/version-format.md)
- **Data Model**: [data-model.md](data-model.md)
- **Research**: [research.md](research.md)
