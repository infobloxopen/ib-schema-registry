# Quickstart: Using Automated Helm Chart Publishing

**Feature**: 005-helm-chart-automation  
**Date**: January 17, 2026  
**Audience**: Developers and users of ib-schema-registry

---

## Overview

Helm charts for `ib-schema-registry` are now automatically published to GitHub Container Registry (GHCR) as OCI artifacts whenever Docker images are built. Chart versions are synchronized with Docker image versions, eliminating manual publishing steps and version drift.

---

## For Users: Installing the Helm Chart

### Prerequisites

- Helm 3.8+ installed ([installation guide](https://helm.sh/docs/intro/install/))
- Access to GitHub Container Registry (public for public repositories)
- Kubernetes cluster (kubectl configured)

### Install Stable Release

```bash
# Find available versions at: https://github.com/infobloxopen/ib-schema-registry/pkgs/container/ib-schema-registry

# Install specific version
helm install my-registry oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3

# Verify installation
kubectl get pods -l app.kubernetes.io/name=ib-schema-registry
kubectl get svc my-registry-ib-schema-registry
```

### Install Development Build

```bash
# Development versions follow format: 0.0.0-<branch>.<short-sha>
# Example: 0.0.0-main.abc1234

helm install my-dev-registry oci://ghcr.io/infobloxopen/ib-schema-registry --version 0.0.0-main.abc1234

# Note: Development builds are for testing unreleased features
```

### Pull Chart Without Installing

```bash
# Download chart locally for inspection
helm pull oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3

# Extract and inspect
tar -xzf ib-schema-registry-1.2.3.tgz
cd ib-schema-registry/
cat Chart.yaml
cat values.yaml
```

### Upgrade Existing Installation

```bash
# Upgrade to new version
helm upgrade my-registry oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.4

# Rollback if needed
helm rollback my-registry
```

### Uninstall

```bash
helm uninstall my-registry
```

---

## For Developers: How Automation Works

### Version Synchronization

Every push to `main` branch or git tag triggers:

1. **Docker Image Build**: Multi-arch image built and pushed to GHCR
2. **SBOM Generation**: Security attestations created for both architectures
3. **Helm Chart Publishing**: Chart automatically packaged and pushed to GHCR with synchronized version

**Version Mapping**:

| Git Event | Docker Image Tag | Helm Chart Version | Example |
|-----------|------------------|--------------------| --------|
| Tag `v1.2.3` | `1.2.3` | `1.2.3` | Production release |
| Branch `main` | `sha-abc1234` | `0.0.0-main.abc1234` | Development build |
| PR #123 | (not pushed) | (not published) | Testing only |

### Checking Build Status

```bash
# View latest workflow run
gh run list --repo infobloxopen/ib-schema-registry --limit 5

# Check specific run details
gh run view <run-id> --repo infobloxopen/ib-schema-registry

# Look for log output:
# 🚀 Published chart: oci://ghcr.io/infobloxopen/ib-schema-registry:1.2.3
```

### Verifying Published Charts

```bash
# List available chart versions (via GHCR UI or API)
# UI: https://github.com/infobloxopen/ib-schema-registry/pkgs/container/ib-schema-registry

# Pull chart to verify version
helm pull oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3
tar -xzf ib-schema-registry-1.2.3.tgz
grep "^version:" ib-schema-registry/Chart.yaml
grep "^appVersion:" ib-schema-registry/Chart.yaml

# Both should output: 1.2.3
```

---

## For Maintainers: Publishing New Releases

### Automated Release Process

1. **Prepare Release**:
   ```bash
   # Ensure all changes are merged to main
   git checkout main
   git pull origin main
   
   # Verify upstream Schema Registry submodule is at desired version
   cd upstream/schema-registry
   git describe --tags  # Should show target version
   ```

2. **Create Release Tag**:
   ```bash
   # Tag format: vMAJOR.MINOR.PATCH (must start with 'v')
   git tag -a v1.2.3 -m "Release Schema Registry 1.2.3 with Infoblox customizations"
   git push origin v1.2.3
   ```

3. **Monitor Workflow**:
   ```bash
   # Watch GitHub Actions workflow
   gh run watch
   
   # Verify completion:
   # - Docker image built: ghcr.io/infobloxopen/ib-schema-registry:1.2.3
   # - Helm chart published: oci://ghcr.io/infobloxopen/ib-schema-registry:1.2.3
   ```

4. **Validate Release**:
   ```bash
   # Test Docker image
   docker pull ghcr.io/infobloxopen/ib-schema-registry:1.2.3
   docker run --rm ghcr.io/infobloxopen/ib-schema-registry:1.2.3 --version
   
   # Test Helm chart
   helm pull oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3
   helm install test-release oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3 --dry-run
   ```

5. **Create GitHub Release**:
   ```bash
   gh release create v1.2.3 --title "v1.2.3" --notes "See CHANGELOG.md for details"
   ```

### Manual Chart Publishing (Fallback)

If automation fails, use Makefile targets:

```bash
# Set version
export CHART_VERSION=1.2.3

# Package chart
make helm-package

# Authenticate to GHCR
echo $GITHUB_TOKEN | helm registry login ghcr.io -u <username> --password-stdin

# Push chart
make helm-push
```

---

## For Developers: Local Development

### Testing Chart Changes Locally

```bash
# Make changes to helm/ib-schema-registry/ templates or values

# Lint chart
cd helm/ib-schema-registry
helm lint .

# Package chart locally
helm package .

# Test installation (local chart)
helm install test-local ./ib-schema-registry-0.1.0.tgz --dry-run --debug

# Render templates only
helm template test-local . --debug
```

### Simulating CI/CD Behavior

```bash
# Simulate version transformation for branch build
VERSION="main"
SHORT_SHA="$(git rev-parse HEAD | cut -c1-7)"

if [[ "$VERSION" != *"."* ]]; then
  VERSION="0.0.0-${VERSION}.${SHORT_SHA}"
fi

echo "Chart version would be: $VERSION"

# Update Chart.yaml (destructive - commit changes or reset after)
sed -i.bak "s/^version:.*/version: ${VERSION}/" helm/ib-schema-registry/Chart.yaml
sed -i.bak "s/^appVersion:.*/appVersion: \"${VERSION}\"/" helm/ib-schema-registry/Chart.yaml

# Package and inspect
helm package helm/ib-schema-registry/
tar -xzf ib-schema-registry-${VERSION}.tgz
cat ib-schema-registry/Chart.yaml

# Cleanup
rm -rf ib-schema-registry/ ib-schema-registry-*.tgz
mv helm/ib-schema-registry/Chart.yaml.bak helm/ib-schema-registry/Chart.yaml
```

---

## For CI/CD Engineers: Workflow Details

### Workflow Integration Points

**File**: `.github/workflows/build-image.yml`

**Step Location**: After SBOM attestations, before test job

**Condition**: Only on `push` events (branches and tags), not PRs

**Execution Flow**:
```
1. Checkout → 2. Build Docker Image → 3. Generate SBOM → 
4. Package Helm Chart → 5. Push to GHCR → 6. Run Tests
```

### Key Environment Variables

```yaml
REGISTRY: ghcr.io
IMAGE_NAME: ${{ github.repository }}  # infobloxopen/ib-schema-registry
VERSION: ${{ steps.meta.outputs.version }}  # From metadata-action
GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}  # Automatic, packages:write permission
```

### Error Handling

The chart publishing step uses `continue-on-error: true` to ensure Docker image availability even if chart publishing fails. Errors are logged as warnings but do not fail the build.

**Example error log**:
```
::warning::Helm chart publishing failed - Docker image published successfully
```

### Debugging Failed Chart Publishes

```bash
# Check workflow logs for step: "Package and publish Helm chart"
gh run view <run-id> --log --repo infobloxopen/ib-schema-registry

# Common failure causes:
# 1. Helm CLI not available (unlikely - ubuntu-latest includes Helm)
# 2. GITHUB_TOKEN missing packages:write permission (check workflow permissions)
# 3. Chart.yaml syntax invalid (validate with helm lint locally)
# 4. Network timeout during push (transient - retry workflow)
```

---

## Troubleshooting

### Issue: "Chart not found" when pulling

**Symptom**: `helm pull oci://... --version X.Y.Z` fails with "not found"

**Causes**:
1. Chart not yet published (check workflow completion)
2. Wrong version number (verify tag/branch format)
3. Authentication required (private repository)

**Solution**:
```bash
# Check GHCR for available versions
# Navigate to: https://github.com/infobloxopen/ib-schema-registry/pkgs/container/ib-schema-registry

# Authenticate if repository is private
echo $GITHUB_TOKEN | helm registry login ghcr.io -u <username> --password-stdin
```

### Issue: Version mismatch between Docker and Helm

**Symptom**: Docker image has version `1.2.3`, Helm chart has different version

**Root Cause**: Workflow automation bypassed (manual chart publish)

**Solution**: Rely on automated publishing. If manual publish needed, ensure version matches Docker image exactly.

### Issue: Chart.yaml shows placeholder version (0.1.0) in git

**Expected Behavior**: Chart.yaml in git repository contains placeholder values. Actual versions are set dynamically during CI/CD build and not committed back to git.

**Verification**: Pull published chart from GHCR to see actual version, not git repository version.

---

## Best Practices

### For Chart Consumers

1. **Pin specific versions** in production: `--version 1.2.3` (not `latest`)
2. **Test upgrades in staging** before production deployment
3. **Review CHANGELOG** before upgrading to understand breaking changes
4. **Use development builds** (`0.0.0-*`) only for testing unreleased features

### For Chart Developers

1. **Test chart changes locally** with `helm lint` and `helm install --dry-run` before pushing
2. **Update chart documentation** (README, comments) when adding new values or features
3. **Follow semver** for version tags (`v1.2.3` format)
4. **Keep Chart.yaml placeholder** (`version: 0.1.0`) in git; automation handles actual versions

### For Release Managers

1. **Use annotated tags**: `git tag -a v1.2.3 -m "Description"` (not lightweight tags)
2. **Verify workflow success** before announcing release
3. **Test published artifacts** (both Docker image and Helm chart) before broader communication
4. **Update CHANGELOG** to document user-facing changes

---

## Additional Resources

- **Helm OCI Documentation**: https://helm.sh/docs/topics/registries/
- **GitHub Container Registry**: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- **Semantic Versioning**: https://semver.org/
- **Project README**: [README.md](../../../README.md)
- **Chart README**: [helm/ib-schema-registry/README.md](../../../helm/ib-schema-registry/README.md)

---

## Quick Reference

### Install Chart
```bash
helm install <release-name> oci://ghcr.io/infobloxopen/ib-schema-registry --version <version>
```

### Upgrade Chart
```bash
helm upgrade <release-name> oci://ghcr.io/infobloxopen/ib-schema-registry --version <new-version>
```

### Pull Chart
```bash
helm pull oci://ghcr.io/infobloxopen/ib-schema-registry --version <version>
```

### Publish Release (Maintainers)
```bash
git tag -a v1.2.3 -m "Release 1.2.3"
git push origin v1.2.3
# Automation handles rest
```

### Manual Publish (Fallback)
```bash
export CHART_VERSION=1.2.3
make helm-package
echo $GITHUB_TOKEN | helm registry login ghcr.io -u <username> --password-stdin
make helm-push
```

---

## Support

For issues or questions:
- **Bug reports**: [GitHub Issues](https://github.com/infobloxopen/ib-schema-registry/issues)
- **Documentation**: [README.md](../../../README.md)
- **Contributing**: [CONTRIBUTING.md](../../../CONTRIBUTING.md)
