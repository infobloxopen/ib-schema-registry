# Local Provenance Testing Guide

**Purpose**: Test SLSA provenance generation locally before pushing to CI  
**Date**: 2025-01-17

## Prerequisites

- Docker with buildx support (Docker Desktop 20.10+ or Docker CLI with buildx plugin)
- BuildKit backend enabled

## Verify Buildx Installation

```bash
# Check if buildx is available
docker buildx version

# List available builders
docker buildx ls

# Create a new builder with full provenance support (if needed)
docker buildx create --name provenance-builder --driver docker-container --use
docker buildx inspect --bootstrap
```

## Build with Provenance Locally

### Single Architecture Build

```bash
# Build for local architecture with provenance
docker buildx build \
  --provenance=mode=max \
  --tag ib-schema-registry:test \
  --load \
  .

# Note: --load only works with single platform builds
# Provenance is generated but may not be fully attached when using --load
```

### Multi-Architecture Build (Recommended)

```bash
# Build for multiple architectures and push to local registry
docker buildx build \
  --provenance=mode=max \
  --platform linux/amd64,linux/arm64 \
  --tag localhost:5000/ib-schema-registry:test \
  --push \
  .

# Note: Requires a local registry running (see below)
```

## Setting Up Local Registry for Testing

```bash
# Start a local registry
docker run -d -p 5000:5000 --name registry registry:2

# Build and push with provenance
docker buildx build \
  --provenance=mode=max \
  --platform linux/amd64,linux/arm64 \
  --build-arg VERSION=test \
  --build-arg REVISION=local-test \
  --build-arg CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --build-arg SOURCE_REPOSITORY=https://github.com/infobloxopen/ib-schema-registry \
  --build-arg SOURCE_COMMIT=local-test \
  --build-arg BUILD_WORKFLOW=local-build \
  --tag localhost:5000/ib-schema-registry:test \
  --push \
  .

# Inspect the provenance
docker buildx imagetools inspect \
  localhost:5000/ib-schema-registry:test \
  --format '{{json .Provenance}}'

# Inspect specific architecture
docker buildx imagetools inspect \
  localhost:5000/ib-schema-registry:test \
  --format '{{json .Provenance}}' \
  --platform linux/amd64

# View the provenance in readable format
docker buildx imagetools inspect \
  localhost:5000/ib-schema-registry:test \
  --format '{{json .Provenance}}' | jq '.'
```

## Verify Provenance Content

```bash
# Extract and validate provenance structure
docker buildx imagetools inspect \
  localhost:5000/ib-schema-registry:test \
  --format '{{json .Provenance}}' | jq '.SLSA'

# Check for required fields
docker buildx imagetools inspect \
  localhost:5000/ib-schema-registry:test \
  --format '{{json .Provenance}}' | jq '{
    predicateType: .SLSA.predicateType,
    builder: .SLSA.predicate.builder.id,
    invocation: .SLSA.predicate.invocation,
    metadata: .SLSA.predicate.metadata
  }'
```

## Expected Provenance Content

The provenance should include:

- **Predicate Type**: `https://slsa.dev/provenance/v1`
- **Builder ID**: BuildKit builder information
- **Build Materials**:
  - Dockerfile location
  - Base image digests
  - Build context
- **Build Invocation**:
  - Build arguments (VERSION, REVISION, etc.)
  - Configuration parameters
- **Metadata**:
  - Build start/completion times
  - Build duration
  - Reproducibility information

## Troubleshooting

### "provenance is not supported" Error

```bash
# Ensure you're using a container driver
docker buildx create --name provenance-builder --driver docker-container --use
docker buildx inspect --bootstrap

# Retry build
docker buildx build --provenance=mode=max ...
```

### Cannot Use --load with Multi-Platform

Multi-platform builds with provenance require `--push` to a registry:

```bash
# Option 1: Use local registry (recommended for testing)
docker run -d -p 5000:5000 --name registry registry:2
docker buildx build --provenance=mode=max --platform linux/amd64,linux/arm64 --push --tag localhost:5000/test .

# Option 2: Build single platform with --load
docker buildx build --provenance=mode=max --platform linux/amd64 --load --tag test:local .
```

### Provenance Not Visible

Provenance attachments may not be visible when using `--load`. Use `--push` to a registry (local or remote) to properly attach attestations:

```bash
# Push to local registry
docker buildx build \
  --provenance=mode=max \
  --platform linux/amd64,linux/arm64 \
  --push \
  --tag localhost:5000/ib-schema-registry:test \
  .

# Verify with imagetools
docker buildx imagetools inspect localhost:5000/ib-schema-registry:test
```

## Cleanup

```bash
# Stop local registry
docker stop registry
docker rm registry

# Remove test builder
docker buildx rm provenance-builder

# Clean up test images
docker rmi localhost:5000/ib-schema-registry:test
```

## Next Steps

After successful local testing:

1. Verify the provenance content is complete
2. Check that all required metadata is present
3. Test with different build arguments
4. Push changes to CI and verify GitHub Actions OIDC signing works
5. Use cosign/slsa-verifier for full signature verification in CI

## CI vs Local Differences

| Feature | Local Build | GitHub Actions |
|---------|-------------|----------------|
| Provenance Generation | ✅ Yes | ✅ Yes |
| Attestation Signing | ❌ No (unsigned) | ✅ Yes (GitHub OIDC) |
| Signature Verification | ❌ Not applicable | ✅ cosign/slsa-verifier |
| Trust Chain | ❌ No trust | ✅ Sigstore + GitHub |

Local provenance is useful for:
- Testing provenance structure
- Validating metadata completeness
- Debugging build issues
- Development workflow

GitHub Actions provenance adds:
- Cryptographic signatures
- Verifiable identity (OIDC)
- Transparency log (Rekor)
- Supply-chain trust
