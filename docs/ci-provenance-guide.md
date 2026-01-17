# CI Provenance Generation Guide

**Purpose**: Understanding how provenance attestations are generated across different CI triggers  
**Date**: 2025-01-17  
**Audience**: Maintainers, contributors, CI/CD engineers

## Overview

This repository automatically generates SLSA provenance attestations for all container images published to the registry. The behavior varies depending on how the build was triggered.

## Provenance Behavior by Trigger

| Trigger | Builds | Pushes to Registry | Generates Provenance | Attestation Signed |
|---------|--------|-------------------|---------------------|-------------------|
| **Pull Request** | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **Push to main** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes (GitHub OIDC) |
| **Tag (v*.*.*)** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes (GitHub OIDC) |
| **Manual dispatch** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes (GitHub OIDC) |

## Pull Request Builds

### Behavior

When you open or update a pull request:

1. ✅ Image is built for both architectures (linux/amd64, linux/arm64)
2. ✅ Build cache is used and updated
3. ❌ Image is NOT pushed to GHCR
4. ❌ Provenance attestation is NOT generated
5. ✅ Build validation ensures no regressions

### Rationale

Pull requests don't push images to the registry, so provenance attestation generation is skipped. This:
- **Saves time**: Provenance generation adds ~5-10 seconds
- **Reduces complexity**: No OIDC token or registry permissions needed
- **Keeps workflow simple**: Focus on build validation, not artifact publishing

### Workflow Configuration

```yaml
# Provenance is conditionally disabled for PRs
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    push: ${{ github.event_name != 'pull_request' }}
    provenance: ${{ github.event_name != 'pull_request' && 'mode=max' || 'false' }}
```

### Verification

```bash
# PR builds show:
Event: pull_request
Provenance: Skipped (PR build)

# No image is pushed, so no attestation is needed
```

## Push to Main Branch

### Behavior

When commits are pushed to the `main` branch:

1. ✅ Image is built for both architectures
2. ✅ Image is pushed to GHCR with tags:
   - `sha-<commit-sha>` (e.g., `sha-abc123...`)
   - `main` (rolling tag)
   - `latest` (rolling tag)
3. ✅ Provenance attestations are generated for each architecture
4. ✅ Attestations are signed using GitHub Actions OIDC token
5. ✅ Attestations are pushed to GHCR alongside the image

### Image Tags

```bash
# After push to main:
ghcr.io/infobloxopen/ib-schema-registry:main
ghcr.io/infobloxopen/ib-schema-registry:latest
ghcr.io/infobloxopen/ib-schema-registry:sha-abc123def456...
```

### Provenance Content

Attestations include:

- **Source Repository**: `https://github.com/infobloxopen/ib-schema-registry`
- **Source Commit**: Full commit SHA
- **Build Workflow**: `Build Multi-Arch Schema Registry Image@refs/heads/main`
- **Builder Identity**: GitHub Actions + BuildKit
- **Build Timestamp**: When the build started and completed
- **Materials**: Source repository, Dockerfile, base images

### Verification

```bash
# Verify main branch image
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/.github/workflows/build-image.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:main

# Check commit SHA matches
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:main \
  | jq -r '.payload | @base64d | fromjson | .predicate.invocation.configSource.digest.sha1'
```

### Workflow Configuration

```yaml
on:
  push:
    branches:
      - main

jobs:
  build:
    permissions:
      id-token: write  # Required for OIDC token
      packages: write  # Required for pushing to GHCR
      contents: read

    steps:
      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          push: true
          provenance: mode=max
          build-args: |
            SOURCE_REPOSITORY=https://github.com/${{ github.repository }}
            SOURCE_COMMIT=${{ github.sha }}
            BUILD_WORKFLOW=${{ github.workflow }}@${{ github.ref }}
```

## Tag (Release) Builds

### Behavior

When you create a Git tag (e.g., `v1.0.0`):

1. ✅ Image is built for both architectures
2. ✅ Image is pushed to GHCR with tags:
   - `v1.0.0` (exact version)
   - `v1.0` (major.minor)
   - `v1` (major)
   - `sha-<commit-sha>` (commit SHA)
   - `latest` (if tag is on main branch)
3. ✅ Provenance attestations are generated for each architecture
4. ✅ Attestations are signed using GitHub Actions OIDC token
5. ✅ Attestations include the **tag reference** in build workflow metadata

### Image Tags

```bash
# After tagging v1.0.0:
ghcr.io/infobloxopen/ib-schema-registry:v1.0.0
ghcr.io/infobloxopen/ib-schema-registry:v1.0
ghcr.io/infobloxopen/ib-schema-registry:v1
ghcr.io/infobloxopen/ib-schema-registry:latest
ghcr.io/infobloxopen/ib-schema-registry:sha-abc123def456...
```

### Provenance Content

Attestations include:

- **Source Repository**: `https://github.com/infobloxopen/ib-schema-registry`
- **Source Commit**: Commit SHA of the tag
- **Build Workflow**: `Build Multi-Arch Schema Registry Image@refs/tags/v1.0.0`
- **Builder Identity**: GitHub Actions + BuildKit
- **Build Timestamp**: When the release build started and completed

### Verification

```bash
# Verify release image against specific tag
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity 'https://github.com/infobloxopen/ib-schema-registry/.github/workflows/build-image.yml@refs/tags/v1.0.0' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:v1.0.0

# Or use slsa-verifier for tag verification
slsa-verifier verify-image \
  ghcr.io/infobloxopen/ib-schema-registry:v1.0.0 \
  --source-uri github.com/infobloxopen/ib-schema-registry \
  --source-tag v1.0.0
```

### Creating a Release

```bash
# Step 1: Tag the commit
git tag v1.0.0
git push origin v1.0.0

# Step 2: GitHub Actions automatically:
# - Builds multi-arch image
# - Generates provenance attestations
# - Signs attestations with OIDC token
# - Pushes image + attestations to GHCR

# Step 3: Verify the release
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:v1.0.0
```

## Manual Workflow Dispatch

### Behavior

When you manually trigger the workflow from the Actions UI:

1. ✅ Image is built for both architectures
2. ✅ Image is pushed to GHCR with branch-specific tags
3. ✅ Provenance attestations are generated
4. ✅ Attestations are signed using GitHub Actions OIDC token

### Triggering Manually

```bash
# Via GitHub UI:
# 1. Go to Actions tab
# 2. Select "Build Multi-Arch Schema Registry Image"
# 3. Click "Run workflow"
# 4. Select branch
# 5. Click "Run workflow"

# Via GitHub CLI:
gh workflow run build-image.yml --ref main
```

## OIDC Token and Signing

### What is OIDC?

OpenID Connect (OIDC) is an identity layer that allows GitHub Actions to obtain short-lived tokens proving the workflow's identity. These tokens are used to sign provenance attestations.

### OIDC Token Claims

The GitHub OIDC token includes claims that prove:

- **Repository**: `infobloxopen/ib-schema-registry`
- **Workflow**: `.github/workflows/build-image.yml`
- **Ref**: `refs/heads/main` or `refs/tags/v1.0.0`
- **SHA**: Git commit SHA
- **Actor**: User who triggered the workflow
- **Event**: `push`, `tag`, etc.

### Signature Verification

When you verify an attestation with cosign, you're checking:

1. **Signature validity**: Cryptographic signature is valid
2. **Certificate identity**: Workflow identity matches expected value
3. **OIDC issuer**: Token was issued by GitHub (`token.actions.githubusercontent.com`)
4. **Transparency log**: Signature was logged in Sigstore Rekor

```bash
# Example verification checking all of the above
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity 'https://github.com/infobloxopen/ib-schema-registry/.github/workflows/build-image.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest
```

### No Secret Management Required

The OIDC token is automatically provided by GitHub Actions:

- ✅ No private keys to store
- ✅ No secret rotation needed
- ✅ No risk of key compromise
- ✅ Short-lived tokens (expires after workflow)

## Build Cache Behavior

### Cache and Provenance

Build cache works seamlessly with provenance generation:

- **Cache source**: `type=gha` (GitHub Actions cache)
- **Cache mode**: `mode=max` (cache all layers)
- **Provenance impact**: Minimal (~5-10 seconds added)
- **Cache invalidation**: Provenance generation doesn't break cache

### Cache Keys

```yaml
cache-from: type=gha  # Pull cache from GitHub Actions
cache-to: type=gha,mode=max  # Push cache to GitHub Actions
```

Cache is scoped to:
- Repository
- Branch (main, feature branches)
- Workflow file

### Verifying Cache Usage

```bash
# In build logs, look for:
# importing cache manifest from gha:... (✅ cache hit)
# exporting cache to gha:... (✅ cache push)
```

## Multi-Architecture Builds

### Architecture-Specific Attestations

Each architecture gets its own provenance attestation:

```bash
# Verify amd64 attestation
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --platform linux/amd64

# Verify arm64 attestation
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --platform linux/arm64
```

### Multi-Arch Manifest

The image manifest list references both:
- Architecture-specific image manifests
- Architecture-specific attestation manifests

```bash
# Inspect manifest list
docker buildx imagetools inspect ghcr.io/infobloxopen/ib-schema-registry:latest

# Shows:
# - Manifest list digest
# - linux/amd64 manifest + attestation
# - linux/arm64 manifest + attestation
```

## Performance Impact

### Build Time Comparison

| Scenario | Without Provenance | With Provenance | Increase |
|----------|-------------------|-----------------|----------|
| **Cold build** (no cache) | ~15 min | ~15.5 min | +3% |
| **Warm build** (cache hit) | ~5 min | ~5.5 min | +10% |
| **Multi-arch** | ~15 min | ~15.5 min | +3% |

### Breakdown

- **Provenance generation**: ~5-10 seconds
- **Attestation signing**: ~2-3 seconds
- **Attestation upload**: ~2-5 seconds
- **Total overhead**: ~10-20 seconds

The overhead is minimal because:
- Provenance is generated in parallel with the build
- OIDC token retrieval is fast
- Attestation upload is asynchronous

## Troubleshooting

### PR Builds Not Generating Provenance

**Expected behavior**: PRs intentionally skip provenance generation.

**Reason**: PRs don't push images, so attestations aren't needed.

**Verification**:
```bash
# In PR build logs, you'll see:
Event: pull_request
Provenance: Skipped (PR build)
```

### Attestation Not Found Immediately After Build

**Symptom**: Build succeeds, but `cosign verify-attestation` fails immediately after.

**Cause**: Attestation upload is asynchronous and may take 10-30 seconds.

**Resolution**: Wait a moment and retry:
```bash
sleep 10
cosign verify-attestation ...
```

### "no matching attestations" Error

**Cause**: Attestation wasn't generated or uploaded successfully.

**Diagnosis**:
1. Check build logs for attestation generation errors
2. Verify `provenance: mode=max` is set in workflow
3. Ensure `id-token: write` permission is granted
4. Confirm image was pushed (`push: true`)

See [troubleshooting-provenance.md](troubleshooting-provenance.md) for detailed diagnostics.

## Best Practices

### For Contributors

1. **PR builds**: Don't worry about provenance - it's automatically skipped
2. **Testing changes**: Use `make build` locally (no provenance) or wait for CI
3. **Reviewing PRs**: Provenance validation happens after merge to main

### For Maintainers

1. **Releases**: Always use semantic version tags (v1.0.0)
2. **Verification**: Verify attestations after each release
3. **Monitoring**: Check CI logs for attestation generation status
4. **Updates**: Pin action versions to avoid breaking changes

### For Consumers

1. **Always verify provenance** before deploying to production
2. **Use specific tags** (not `latest`) for reproducibility
3. **Check source commit** matches expected release
4. **Verify builder identity** is GitHub Actions

## Additional Resources

- **Provenance Verification Guide**: [provenance-verification.md](provenance-verification.md)
- **Troubleshooting Guide**: [troubleshooting-provenance.md](troubleshooting-provenance.md)
- **SLSA Framework**: https://slsa.dev/
- **GitHub Actions OIDC**: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect

## Examples

### Verify Latest Main Build

```bash
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/.github/workflows/build-image.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:main
```

### Verify Specific Release

```bash
slsa-verifier verify-image \
  ghcr.io/infobloxopen/ib-schema-registry:v1.0.0 \
  --source-uri github.com/infobloxopen/ib-schema-registry \
  --source-tag v1.0.0
```

### Extract Build Metadata

```bash
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  | jq -r '.payload | @base64d | fromjson | .predicate | {
      source: .invocation.configSource.uri,
      commit: .invocation.configSource.digest.sha1,
      workflow: .invocation.parameters.args.BUILD_WORKFLOW,
      timestamp: .metadata.buildStartedOn
    }'
```
