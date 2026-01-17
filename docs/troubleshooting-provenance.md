# Provenance Generation Troubleshooting Guide

**Purpose**: Diagnose and resolve SLSA provenance generation issues in CI/CD  
**Date**: 2025-01-17  
**Audience**: Maintainers, CI/CD engineers

## Overview

This guide helps troubleshoot issues with SLSA provenance attestation generation in GitHub Actions builds. Provenance generation happens automatically during the Docker build process and should be transparent, but this guide covers common issues when things go wrong.

## Quick Diagnostics

### Check Build Logs

1. Navigate to the failed workflow run in GitHub Actions
2. Expand the "Build and push Docker image" step
3. Look for error messages related to:
   - Attestation generation
   - BuildKit attestation builder
   - Registry upload errors

### Common Error Patterns

```bash
# Build succeeded but attestation failed
✅ Build completed
❌ Error uploading attestation: ...

# Attestation generation not supported
❌ provenance is not supported for driver ...

# Registry rejection
❌ Error pushing attestation manifest: 403 Forbidden
```

## Issue Categories

### 1. Provenance Not Generated

**Symptoms**:
- Build succeeds
- No error messages
- Verification shows no attestation

**Diagnosis**:

```bash
# Check if provenance parameter is set in workflow
grep -A 10 "build-push-action" .github/workflows/build-image.yml | grep provenance

# Should show:
# provenance: mode=max
```

**Common Causes**:

#### A. PR Build (Expected Behavior)

Provenance is intentionally skipped for pull requests to avoid registry pushes.

```yaml
# In build-image.yml
provenance: ${{ github.event_name != 'pull_request' && 'mode=max' || 'false' }}
```

**Resolution**: This is normal. PR builds don't push images, so they don't generate attestations.

**Verification**:
```bash
# Check workflow run
echo "${{ github.event_name }}"  # Should show 'pull_request'
```

#### B. Docker Buildx Driver Issue

BuildKit container driver is required for attestation support.

**Resolution**:

```yaml
# Ensure docker/setup-buildx-action is present
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3
```

**Verification**:
```bash
# In CI logs, should see:
# Buildx driver: docker-container
```

#### C. Provenance Parameter Missing or Disabled

**Resolution**:

```yaml
# Ensure provenance is enabled in build step
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    provenance: mode=max  # Must be present and enabled
```

### 2. OIDC Token Issues

**Symptoms**:
- Build succeeds
- Attestation generated but unsigned
- "failed to get OIDC token" errors

**Diagnosis**:

```yaml
# Check permissions in workflow
jobs:
  build:
    permissions:
      id-token: write  # Must be present
      packages: write
      contents: read
```

**Common Causes**:

#### A. Missing id-token Permission

**Resolution**:

```yaml
# Add to job permissions
permissions:
  id-token: write  # Required for GitHub OIDC token
  packages: write
  contents: read
```

#### B. Organization/Repository Settings

Some organizations disable OIDC tokens by default.

**Resolution**:
1. Go to Repository Settings → Actions → General
2. Ensure "Allow GitHub Actions to create and approve pull requests" is enabled
3. Check organization-level OIDC restrictions

**Verification**:
```bash
# In CI logs, look for:
# Successfully obtained OIDC token
# Certificate identity: https://github.com/...
```

### 3. Registry Upload Failures

**Symptoms**:
- Build succeeds
- Attestation generated
- "error uploading attestation" or "403 Forbidden"

**Diagnosis**:

Check registry permissions:
```yaml
permissions:
  packages: write  # Required for GHCR
```

**Common Causes**:

#### A. Insufficient Registry Permissions

**Resolution**:

```yaml
# Ensure packages: write is set
jobs:
  build:
    permissions:
      packages: write  # Must be present
```

#### B. Registry Authentication Failure

**Resolution**:

```yaml
# Verify login step exists and uses correct token
- name: Log in to GitHub Container Registry
  if: github.event_name != 'pull_request'
  uses: docker/login-action@v3
  with:
    registry: ${{ env.REGISTRY }}
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}  # Must have packages scope
```

#### C. Organization/Repository Visibility Issues

GHCR packages inherit repository visibility (public/private).

**Resolution**:
1. Go to Package settings in GHCR
2. Ensure write access is granted to the repository
3. Check that GITHUB_TOKEN has necessary scopes

### 4. Multi-Architecture Issues

**Symptoms**:
- Attestation exists for one architecture but not others
- "platform not found" errors during verification

**Diagnosis**:

```bash
# Verify multi-arch build configuration
grep -A 5 "platforms:" .github/workflows/build-image.yml

# Should show:
# platforms: linux/amd64,linux/arm64
```

**Common Causes**:

#### A. QEMU Not Set Up

Multi-arch builds require QEMU for emulation.

**Resolution**:

```yaml
# Ensure QEMU setup step is present and runs before build
- name: Set up QEMU
  uses: docker/setup-qemu-action@v3

- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3
```

**Verification**:
```bash
# In CI logs, should see:
# Setting up QEMU...
# QEMU platforms: linux/amd64,linux/arm64,...
```

#### B. Platform-Specific Build Failures

One architecture builds successfully but another fails.

**Resolution**:

Check build logs for architecture-specific errors:
```bash
# Look for platform-specific errors in logs
# Example: "exec format error" indicates wrong binary architecture
```

Test locally:
```bash
# Test single architecture
docker buildx build --platform linux/amd64 --provenance=mode=max .
docker buildx build --platform linux/arm64 --provenance=mode=max .
```

### 5. Cache Conflicts

**Symptoms**:
- Provenance worked before but suddenly fails
- "cache manifest not found" errors
- Inconsistent attestation generation

**Diagnosis**:

```yaml
# Check cache configuration
cache-from: type=gha
cache-to: type=gha,mode=max
```

**Resolution**:

Clear GitHub Actions cache:
```bash
# In GitHub UI:
# Repository → Actions → Caches → Delete all caches

# Or via GitHub CLI:
gh cache delete --all
```

Rebuild without cache:
```yaml
# Temporarily disable cache to diagnose
# cache-from: type=gha
# cache-to: type=gha,mode=max
```

### 6. Verification Timing Issues

**Symptoms**:
- Build succeeds
- Attestation generation logs show success
- Immediate verification fails but later verification succeeds

**Explanation**: Registry attestation upload is asynchronous. Attestations may not be immediately queryable.

**Resolution**:

Add delay before verification:
```yaml
- name: Verify attestation attachment
  run: |
    echo "Waiting for attestation upload..."
    sleep 10  # Wait for async upload
    docker buildx imagetools inspect ...
```

Or make verification non-blocking:
```yaml
- name: Verify attestation attachment
  continue-on-error: true  # Don't fail build if attestation not yet available
```

### 7. BuildKit Version Issues

**Symptoms**:
- "unknown flag: --provenance" errors
- "provenance not supported" messages

**Diagnosis**:

```yaml
# Check Docker and BuildKit versions in CI logs
docker version
docker buildx version
```

**Resolution**:

Ensure recent action versions:
```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3  # v3+ required

- name: Build and push Docker image
  uses: docker/build-push-action@v5  # v5+ required
```

**Requirements**:
- docker/setup-buildx-action: v3+
- docker/build-push-action: v5+
- BuildKit: v0.11+

## Debugging Workflow

### Step 1: Verify Prerequisites

```bash
# Check workflow has required setup steps
cat .github/workflows/build-image.yml | grep -E "(setup-qemu|setup-buildx|build-push-action)"

# Should show all three actions present
```

### Step 2: Check Permissions

```bash
# Verify job permissions
grep -A 5 "permissions:" .github/workflows/build-image.yml

# Must include:
# id-token: write
# packages: write
# contents: read
```

### Step 3: Test Local Build

```bash
# Test provenance generation locally
docker buildx create --name test-builder --driver docker-container --use
docker buildx build \
  --provenance=mode=max \
  --platform linux/amd64 \
  --tag test:local \
  --push \
  --registry localhost:5000 \
  .

# Verify attestation
docker buildx imagetools inspect localhost:5000/test:local --format '{{json .Provenance}}'
```

### Step 4: Review CI Logs

Look for specific error patterns:

```bash
# Build errors
grep -i "error" build-logs.txt | grep -i "build"

# Attestation errors
grep -i "error" build-logs.txt | grep -i "attestation\|provenance"

# Registry errors
grep -i "error" build-logs.txt | grep -i "registry\|push\|upload"

# Permission errors
grep -i "error" build-logs.txt | grep -i "permission\|forbidden\|unauthorized"
```

### Step 5: Manual Verification

After build completes:

```bash
# Check if image exists
docker pull ghcr.io/infobloxopen/ib-schema-registry:sha-<commit>

# Inspect image manifest
docker buildx imagetools inspect ghcr.io/infobloxopen/ib-schema-registry:sha-<commit>

# Check for attestation
docker buildx imagetools inspect \
  ghcr.io/infobloxopen/ib-schema-registry:sha-<commit> \
  --format '{{json .Provenance}}'

# If empty, attestation was not attached
```

## Escalation Checklist

Before escalating, gather:

1. **Workflow run URL**: Direct link to failed run
2. **Full build logs**: Download from Actions UI
3. **Workflow file**: Current `.github/workflows/build-image.yml` content
4. **Event type**: PR, push to main, or tag
5. **Error messages**: Specific error text from logs
6. **Verification commands**: Commands used to verify attestation
7. **Expected vs actual**: What should happen vs what happened

## Known Issues

### Issue: "provenance attestation not found" after successful build

**Status**: Expected behavior  
**Cause**: Attestation upload is asynchronous  
**Workaround**: Wait 10-30 seconds before verification or use `continue-on-error: true`

### Issue: PR builds show "provenance skipped"

**Status**: Expected behavior  
**Cause**: PRs don't push to registry, so provenance is disabled  
**Resolution**: None needed - this is intentional

### Issue: Multi-arch manifest shows only one attestation

**Status**: Under investigation  
**Cause**: May be registry-side aggregation  
**Workaround**: Verify each architecture digest individually

## Best Practices

1. **Always include setup steps in order**:
   ```yaml
   - setup-qemu-action
   - setup-buildx-action
   - login-action (if pushing)
   - build-push-action
   ```

2. **Use explicit permissions**:
   ```yaml
   permissions:
     id-token: write
     packages: write
     contents: read
   ```

3. **Add logging for debugging**:
   ```yaml
   - name: Debug info
     run: |
       echo "Event: ${{ github.event_name }}"
       echo "Ref: ${{ github.ref }}"
       docker buildx version
   ```

4. **Make verification non-blocking initially**:
   ```yaml
   - name: Verify attestation
     continue-on-error: true  # Don't block on verification
   ```

5. **Pin action versions**:
   ```yaml
   uses: docker/build-push-action@v5  # Don't use @latest
   ```

## Additional Resources

- **BuildKit Attestations**: https://docs.docker.com/build/attestations/
- **GitHub Actions Permissions**: https://docs.github.com/en/actions/security-guides/automatic-token-authentication
- **Docker Build Push Action**: https://github.com/docker/build-push-action
- **Sigstore Documentation**: https://docs.sigstore.dev/

## Support

For persistent issues:

1. Check [GitHub Actions status](https://www.githubstatus.com/)
2. Review [Docker Build Push Action issues](https://github.com/docker/build-push-action/issues)
3. Open an issue in this repository with the escalation checklist data
