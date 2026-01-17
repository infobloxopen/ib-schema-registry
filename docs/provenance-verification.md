# Provenance Verification Guide

**Purpose**: Guide for verifying SLSA provenance attestations on container images  
**Date**: 2025-01-17  
**Audience**: Security engineers, operations teams, compliance auditors

## Overview

All container images published from this repository include SLSA (Supply-chain Levels for Software Artifacts) provenance attestations. These attestations provide cryptographically verifiable metadata about:

- **What** was built (source code, commit SHA)
- **How** it was built (workflow, build environment)
- **When** it was built (timestamp)
- **Where** it was built (builder identity, GitHub Actions)

## Quick Start

Verify an image in under 30 seconds:

```bash
# Install cosign (one-time setup)
go install github.com/sigstore/cosign/v2/cmd/cosign@latest

# Verify image provenance
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest

# ✅ Success means: signature valid, built by trusted GitHub Actions workflow
```

## Verification Tools

### Option 1: Cosign (Recommended for Signature Verification)

**Best for**: Verifying cryptographic signatures and GitHub Actions identity

#### Installation

```bash
# Using Go
go install github.com/sigstore/cosign/v2/cmd/cosign@latest

# Using Homebrew (macOS/Linux)
brew install cosign

# Using Docker
docker run --rm gcr.io/projectsigstore/cosign version
```

#### Basic Verification

```bash
# Verify signature and extract attestation
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest
```

#### Inspect Attestation Contents

```bash
# Extract and view provenance JSON
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  | jq -r '.payload | @base64d | fromjson | .predicate'
```

#### Verify Specific Source Repository

```bash
# Verify image was built from expected repository
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity 'https://github.com/infobloxopen/ib-schema-registry/.github/workflows/build-image.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest
```

#### Verify Specific Git Tag/Release

```bash
# Verify image was built from specific tag
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/.github/workflows/build-image.yml@refs/tags/v1\.0\.0$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:v1.0.0
```

#### Extract Specific Metadata

```bash
# Get source commit SHA
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  | jq -r '.payload | @base64d | fromjson | .predicate.materials[] | select(.uri | startswith("git+https://github.com")) | .digest.sha1'

# Get build timestamp
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  | jq -r '.payload | @base64d | fromjson | .predicate.metadata.buildStartedOn'

# Get builder identity
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  | jq -r '.payload | @base64d | fromjson | .predicate.builder.id'
```

### Option 2: SLSA Verifier (Recommended for SLSA Compliance)

**Best for**: Validating SLSA provenance schema and source repository matching

#### Installation

```bash
# Using Go
go install github.com/slsa-framework/slsa-verifier/v2/cli/slsa-verifier@latest

# Download binary
wget https://github.com/slsa-framework/slsa-verifier/releases/latest/download/slsa-verifier-linux-amd64
chmod +x slsa-verifier-linux-amd64
sudo mv slsa-verifier-linux-amd64 /usr/local/bin/slsa-verifier
```

#### Basic Verification

```bash
# Verify image against source repository
slsa-verifier verify-image \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --source-uri github.com/infobloxopen/ib-schema-registry \
  --print-provenance
```

#### Verify Specific Tag/Branch

```bash
# Verify against specific tag
slsa-verifier verify-image \
  ghcr.io/infobloxopen/ib-schema-registry:v1.0.0 \
  --source-uri github.com/infobloxopen/ib-schema-registry \
  --source-tag v1.0.0

# Verify against main branch
slsa-verifier verify-image \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --source-uri github.com/infobloxopen/ib-schema-registry \
  --source-branch main
```

#### Verify Builder Identity

```bash
# Verify specific builder (GitHub Actions)
slsa-verifier verify-image \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --source-uri github.com/infobloxopen/ib-schema-registry \
  --builder-id https://github.com/docker/build-push-action/.github/workflows/build.yml
```

### Option 3: Docker Buildx (Recommended for Quick Inspection)

**Best for**: Quick inspection of provenance content without signature verification

#### Inspect Provenance

```bash
# View raw provenance JSON
docker buildx imagetools inspect \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --format '{{json .Provenance}}'

# Pretty-print provenance
docker buildx imagetools inspect \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --format '{{json .Provenance}}' | jq '.'

# Extract specific fields
docker buildx imagetools inspect \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --format '{{json .Provenance}}' | jq '.SLSA.predicate | {
    builder: .builder.id,
    buildType: .buildType,
    materials: .materials | map(.uri),
    timestamp: .metadata.buildStartedOn
  }'
```

#### Check Provenance Exists

```bash
# Quickly check if provenance is present
if docker buildx imagetools inspect ghcr.io/infobloxopen/ib-schema-registry:latest --format '{{json .Provenance}}' | jq -e '.SLSA' > /dev/null; then
  echo "✅ Provenance attestation found"
else
  echo "❌ No provenance attestation"
fi
```

## Multi-Architecture Verification

Images are built for multiple architectures (linux/amd64, linux/arm64). Each architecture has its own provenance attestation.

### List Available Architectures

```bash
# View all architectures in manifest
docker buildx imagetools inspect ghcr.io/infobloxopen/ib-schema-registry:latest

# Output example:
# Name:      ghcr.io/infobloxopen/ib-schema-registry:latest
# MediaType: application/vnd.oci.image.index.v1+json
# Digest:    sha256:abc123...
#
# Manifests:
#   Name:      ghcr.io/infobloxopen/ib-schema-registry:latest@sha256:def456...
#   MediaType: application/vnd.oci.image.manifest.v1+json
#   Platform:  linux/amd64
#
#   Name:      ghcr.io/infobloxopen/ib-schema-registry:latest@sha256:ghi789...
#   MediaType: application/vnd.oci.image.manifest.v1+json
#   Platform:  linux/arm64
```

### Verify Specific Architecture

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

### Verify All Architectures

```bash
#!/bin/bash
# Script to verify all architectures

IMAGE="ghcr.io/infobloxopen/ib-schema-registry:latest"
PLATFORMS=("linux/amd64" "linux/arm64")

for platform in "${PLATFORMS[@]}"; do
  echo "Verifying $platform..."
  if cosign verify-attestation \
    --type slsaprovenance \
    --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    "$IMAGE" \
    --platform "$platform" > /dev/null 2>&1; then
    echo "✅ $platform: Provenance verified"
  else
    echo "❌ $platform: Provenance verification failed"
    exit 1
  fi
done

echo "✅ All architectures verified successfully"
```

## Offline/Air-Gapped Verification

For environments without internet access to Sigstore infrastructure:

### Step 1: Prepare Verification Bundle (Online Environment)

```bash
# Download Sigstore trust root
cosign initialize

# Export image with all attestations
docker pull ghcr.io/infobloxopen/ib-schema-registry:latest
docker save ghcr.io/infobloxopen/ib-schema-registry:latest -o image.tar

# Download attestations
cosign download attestation \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  > attestations.json

# Package for offline transfer
tar czf verification-bundle.tar.gz \
  image.tar \
  attestations.json \
  ~/.sigstore/root.json
```

### Step 2: Transfer to Air-Gapped Environment

Transfer `verification-bundle.tar.gz` to the offline environment using approved methods.

### Step 3: Verify in Air-Gapped Environment

```bash
# Extract bundle
tar xzf verification-bundle.tar.gz

# Restore Sigstore root
mkdir -p ~/.sigstore
cp root.json ~/.sigstore/

# Load image
docker load -i image.tar

# Verify using local attestation
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --offline \
  ghcr.io/infobloxopen/ib-schema-registry:latest

# Alternatively, inspect attestation without signature verification
cat attestations.json | jq '.payload | @base64d | fromjson | .predicate'
```

### Manual Attestation Inspection (No Internet Required)

If Sigstore is unavailable, you can still inspect attestation content:

```bash
# Load image locally
docker load -i image.tar

# Extract provenance using docker buildx (no signature check)
docker buildx imagetools inspect \
  --raw \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  > manifest.json

# Extract attestation references
cat manifest.json | jq '.manifests[] | select(.annotations."vnd.docker.reference.type" == "attestation-manifest")'

# View provenance content
cat attestations.json | jq '.payload | @base64d | fromjson'
```

## Expected Provenance Content

A valid provenance attestation includes:

```json
{
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "builder": {
      "id": "https://github.com/docker/build-push-action@<version>"
    },
    "buildType": "https://mobyproject.org/buildkit@v1",
    "invocation": {
      "configSource": {
        "uri": "https://github.com/infobloxopen/ib-schema-registry",
        "digest": {
          "sha1": "<commit-sha>"
        }
      },
      "parameters": {
        "frontend": "dockerfile.v0",
        "args": {
          "SOURCE_REPOSITORY": "https://github.com/infobloxopen/ib-schema-registry",
          "SOURCE_COMMIT": "<commit-sha>",
          "BUILD_WORKFLOW": "Build Multi-Arch Schema Registry Image@refs/heads/main"
        }
      }
    },
    "materials": [
      {
        "uri": "git+https://github.com/infobloxopen/ib-schema-registry",
        "digest": {
          "sha1": "<commit-sha>"
        }
      },
      {
        "uri": "pkg:docker/...",
        "digest": {
          "sha256": "<base-image-digest>"
        }
      }
    ],
    "metadata": {
      "buildStartedOn": "2025-01-17T...",
      "buildFinishedOn": "2025-01-17T...",
      "completeness": {
        "parameters": true,
        "environment": false,
        "materials": false
      }
    }
  }
}
```

### Key Fields to Verify

- **builder.id**: Should reference GitHub Actions or BuildKit
- **invocation.configSource.uri**: Must match `https://github.com/infobloxopen/ib-schema-registry`
- **invocation.configSource.digest.sha1**: Git commit SHA
- **materials**: Should include source repository and base images
- **metadata.buildStartedOn**: Build timestamp

## Common Verification Scenarios

### Scenario 1: Security Audit

**Goal**: Verify an image was built from trusted source by authorized builder

```bash
# Comprehensive verification
slsa-verifier verify-image \
  ghcr.io/infobloxopen/ib-schema-registry:v1.0.0 \
  --source-uri github.com/infobloxopen/ib-schema-registry \
  --source-tag v1.0.0 \
  --print-provenance

# Verify signature with specific identity
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity 'https://github.com/infobloxopen/ib-schema-registry/.github/workflows/build-image.yml@refs/tags/v1.0.0' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:v1.0.0

# Extract and review build metadata
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:v1.0.0 \
  | jq -r '.payload | @base64d | fromjson | .predicate | {
      source: .invocation.configSource.uri,
      commit: .invocation.configSource.digest.sha1,
      builder: .builder.id,
      buildTime: .metadata.buildStartedOn
    }'
```

### Scenario 2: Compliance Check

**Goal**: Document provenance for compliance reporting

```bash
#!/bin/bash
# Compliance verification script

IMAGE="ghcr.io/infobloxopen/ib-schema-registry:latest"
OUTPUT_FILE="provenance-compliance-report.json"

echo "Generating compliance report for $IMAGE..."

# Verify and extract full provenance
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$IMAGE" \
  | jq '{
      verificationStatus: "PASSED",
      verificationTimestamp: now | todate,
      image: "'$IMAGE'",
      provenance: (.payload | @base64d | fromjson | .predicate)
    }' > "$OUTPUT_FILE"

echo "✅ Compliance report saved to $OUTPUT_FILE"
```

### Scenario 3: Continuous Deployment Validation

**Goal**: Automatically verify provenance before deploying to production

```bash
#!/bin/bash
# Pre-deployment verification

IMAGE="${1:?Usage: $0 <image>}"
REQUIRED_SOURCE="github.com/infobloxopen/ib-schema-registry"
REQUIRED_BRANCH="main"

echo "Verifying image: $IMAGE"

# Verify source repository and branch
if slsa-verifier verify-image \
  "$IMAGE" \
  --source-uri "$REQUIRED_SOURCE" \
  --source-branch "$REQUIRED_BRANCH" \
  > /dev/null 2>&1; then
  echo "✅ Provenance verification passed"
  echo "✅ Source: $REQUIRED_SOURCE"
  echo "✅ Branch: $REQUIRED_BRANCH"
  exit 0
else
  echo "❌ Provenance verification failed"
  echo "Image may not be from trusted source or branch"
  exit 1
fi
```

## Troubleshooting

### "no matching attestations" Error

**Cause**: Attestation not found in registry

```bash
# Check if image exists
docker pull ghcr.io/infobloxopen/ib-schema-registry:latest

# Inspect image to see available attestations
docker buildx imagetools inspect ghcr.io/infobloxopen/ib-schema-registry:latest

# Verify you're using the correct image reference (tag or digest)
```

### "signature verification failed" Error

**Cause**: Certificate identity or OIDC issuer mismatch

```bash
# Use broader regex for certificate identity
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest

# Or inspect certificate without verification
cosign download attestation ghcr.io/infobloxopen/ib-schema-registry:latest \
  | jq -r '.payload | @base64d | fromjson'
```

### Rekor Transparency Log Errors

**Cause**: Network connectivity to Sigstore services

```bash
# Verify network access
curl -I https://rekor.sigstore.dev

# Use offline verification if internet is unavailable
cosign verify-attestation --offline ...

# Or inspect attestation content without signature verification
docker buildx imagetools inspect ... --format '{{json .Provenance}}'
```

## Additional Resources

- **SLSA Framework**: https://slsa.dev/
- **Sigstore Documentation**: https://docs.sigstore.dev/
- **Cosign Documentation**: https://docs.sigstore.dev/cosign/overview/
- **SLSA Verifier**: https://github.com/slsa-framework/slsa-verifier
- **Docker Buildx Attestations**: https://docs.docker.com/build/attestations/

## Support

For issues or questions about provenance verification:

1. Check this documentation first
2. Review build logs in GitHub Actions for attestation generation status
3. Open an issue in the repository with:
   - Image reference (tag or digest)
   - Verification command used
   - Error message received
   - Output of `docker buildx imagetools inspect <image>`
