# GitHub Container Registry Attestation Storage

**Purpose**: Document GHCR behavior, limits, and best practices for provenance attestations  
**Date**: 2025-01-17  
**Audience**: Maintainers, CI/CD engineers

## Overview

GitHub Container Registry (GHCR) stores provenance attestations as separate OCI artifact manifests linked to container images. Understanding GHCR's storage behavior helps prevent unexpected issues and optimize attestation usage.

## How Attestations are Stored

### OCI Artifact Structure

```
ghcr.io/infobloxopen/ib-schema-registry:main
├── Image Manifest (application/vnd.oci.image.manifest.v1+json)
│   ├── Config (application/vnd.oci.image.config.v1+json)
│   ├── Layer 1 (application/vnd.oci.image.layer.v1.tar+gzip)
│   ├── Layer 2 (application/vnd.oci.image.layer.v1.tar+gzip)
│   └── ...
└── Attestation Manifests
    ├── SLSA Provenance (application/vnd.in-toto+json)
    ├── SBOM (application/vnd.cyclonedx+json) - if generated
    └── Custom Attestations - if any
```

### Multi-Architecture Images

For multi-arch images, each architecture has its own attestation:

```
Manifest List (Index)
├── linux/amd64 Image → SLSA Provenance (amd64)
└── linux/arm64 Image → SLSA Provenance (arm64)
```

Attestations are attached to **architecture-specific digests**, not the manifest list.

## Storage Limits

### Current Known Limits (as of 2025-01-17)

| Limit Type | Value | Notes |
|------------|-------|-------|
| **Max attestations per image** | No documented limit | Tested with 10+ attestations successfully |
| **Attestation size** | ~10 MB recommended | Larger attestations may slow queries |
| **Total package size** | 10 GB per package | Includes image + all attestations |
| **Retention** | Indefinite (tied to image) | Attestations deleted when image is deleted |
| **Rate limits** | Standard API limits | ~5000 requests/hour for authenticated users |

> **Note**: GitHub does not publish hard limits for attestation counts. Limits are subject to change.

### Recommendations

- **Keep attestations under 1 MB**: Large attestations slow down verification
- **Limit custom attestations**: Use standard types (SLSA, SBOM) when possible
- **Monitor package size**: GHCR displays total package size in UI
- **Clean up old images**: Attestations are deleted with parent image

## Attestation Types

### Supported Types

GHCR supports any OCI artifact but common types include:

```
application/vnd.in-toto+json             # SLSA provenance (in-toto format)
application/vnd.cyclonedx+json           # CycloneDX SBOM
application/vnd.spdx+json                # SPDX SBOM
application/sarif+json                   # Security scan results
application/vnd.dev.sigstore.bundle+json # Sigstore bundle
```

### This Repository's Attestations

Currently generates:
- ✅ **SLSA Provenance** (`application/vnd.in-toto+json`) - ~5-10 KB

Future possibilities:
- ⏳ **SBOM** (Software Bill of Materials) - ~50-100 KB
- ⏳ **Vulnerability Scan** (Trivy/Grype results) - ~10-50 KB

## Querying Attestations

### List All Attestations

```bash
# Using cosign
cosign download attestation ghcr.io/infobloxopen/ib-schema-registry:main

# Using docker buildx
docker buildx imagetools inspect \
  ghcr.io/infobloxopen/ib-schema-registry:main \
  --format '{{json .Provenance}}'

# Using crane (go-containerregistry)
crane manifest ghcr.io/infobloxopen/ib-schema-registry:main | jq '.attestations'
```

### Check Attestation Size

```bash
# Download attestation
cosign download attestation \
  ghcr.io/infobloxopen/ib-schema-registry:main \
  > attestation.json

# Check size
ls -lh attestation.json
# Example output: -rw-r--r--  1 user  staff   8.2K Jan 17 10:30 attestation.json

# Count attestations
cosign download attestation \
  ghcr.io/infobloxopen/ib-schema-registry:main \
  | jq '. | length'
```

## Retention and Deletion

### Lifecycle

1. **Creation**: Attestations are created during image build and pushed to GHCR
2. **Linking**: Attestations are linked to image digest (immutable)
3. **Retention**: Attestations persist as long as the image exists
4. **Deletion**: Attestations are deleted when the parent image is deleted

### Deleting Specific Attestations

```bash
# WARNING: This will delete the attestation permanently
# Use the attestation digest, not the image digest

# Get attestation digest
ATTESTATION_DIGEST=$(cosign triangulate ghcr.io/infobloxopen/ib-schema-registry:main)

# Delete attestation (requires admin access)
crane delete "${ATTESTATION_DIGEST}"
```

> **Caution**: Deleting attestations breaks provenance verification. Only delete if absolutely necessary (e.g., accidental PII in attestation).

### Cleanup Old Attestations

Attestations are automatically cleaned up when images are deleted:

```bash
# Delete old image (and its attestations)
docker rmi ghcr.io/infobloxopen/ib-schema-registry:sha-old123

# Or via GHCR UI:
# Repository → Packages → Select version → Delete
```

## Rate Limits

### GitHub API Rate Limits

GHCR uses GitHub API infrastructure, so rate limits apply:

| User Type | Requests/Hour | Notes |
|-----------|---------------|-------|
| **Authenticated** | 5,000 | Using GITHUB_TOKEN or PAT |
| **Unauthenticated** | 60 | Public access (very limited) |
| **GitHub Actions** | 15,000 | Higher limit for CI/CD |

### Impact on CI/CD

Each attestation query counts toward rate limits:

```bash
# Each of these operations counts as 1-3 API requests:
cosign verify-attestation ...
docker buildx imagetools inspect ...
crane manifest ...
```

**Best Practices**:
- ✅ Authenticate in CI/CD (use `GITHUB_TOKEN`)
- ✅ Cache verification results
- ✅ Avoid excessive polling
- ❌ Don't query attestations in tight loops

### Checking Rate Limit Status

```bash
# Check remaining API quota
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/rate_limit \
  | jq '.rate'

# Example output:
# {
#   "limit": 5000,
#   "remaining": 4956,
#   "reset": 1705500000,
#   "used": 44
# }
```

## Package Size Monitoring

### Check Total Package Size

Via GHCR UI:
1. Go to GitHub → Packages
2. Select `ib-schema-registry`
3. View "Package size" in sidebar

Via API:
```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/orgs/infobloxopen/packages/container/ib-schema-registry/versions" \
  | jq '.[] | {name, size_in_bytes: .metadata.container.tags}'
```

### Size Breakdown

Typical sizes for this repository:

```
Container Image (linux/amd64):  ~500 MB
Container Image (linux/arm64):  ~500 MB
SLSA Provenance (amd64):        ~10 KB
SLSA Provenance (arm64):        ~10 KB
─────────────────────────────────────────
Total per tag:                  ~1000 MB
```

## Troubleshooting

### "no matching attestations" Error

**Cause**: Attestation not found in GHCR

**Solutions**:
1. Wait 10-30 seconds (attestation upload is asynchronous)
2. Verify image was built via CI (not locally)
3. Check build was on main branch or tag (not PR)
4. Ensure provenance generation is enabled in workflow

### "Rate limit exceeded" Error

**Cause**: Too many API requests

**Solutions**:
```bash
# Authenticate requests
export GITHUB_TOKEN="your_token"

# Or use PAT in Docker
echo "$GITHUB_TOKEN" | docker login ghcr.io -u username --password-stdin

# Check remaining quota
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/rate_limit
```

### Attestation Download is Slow

**Cause**: Large attestation or network issues

**Solutions**:
1. Use `--platform` flag to download specific architecture only
2. Cache attestation locally
3. Use `jq` to filter only needed fields

```bash
# Download and cache
cosign download attestation ghcr.io/infobloxopen/ib-schema-registry:main > cache.json

# Query cache instead of GHCR
cat cache.json | jq '.payload | @base64d | fromjson'
```

## Best Practices

### For Maintainers

1. **Monitor package size**: Check GHCR UI regularly for unexpected growth
2. **Clean up old tags**: Delete unused image tags to free space
3. **Test attestation size**: Verify attestations remain under 1 MB
4. **Document custom attestations**: If adding new types, document purpose and size

### For CI/CD

1. **Authenticate all requests**: Use `GITHUB_TOKEN` in workflows
2. **Cache verification results**: Don't re-verify in every job
3. **Use specific digests**: Pin to digest instead of tag for consistency
4. **Monitor rate limits**: Add rate limit checks to CI

### For Consumers

1. **Verify once, deploy many**: Cache verification result
2. **Use offline bundles**: For air-gapped environments, bundle attestations
3. **Pin to digests**: Use `@sha256:...` for immutable references
4. **Monitor for changes**: Set up alerts if attestations are modified

## Future Considerations

### SBOM Generation

When adding SBOM attestations:
- **Expected size**: 50-100 KB (CycloneDX or SPDX)
- **Frequency**: One per image build
- **Storage impact**: Minimal (< 1% of image size)

### Vulnerability Scans

If adding scan results:
- **Expected size**: 10-50 KB (SARIF format)
- **Frequency**: Per build or scheduled
- **Storage impact**: Low, but could grow with frequent scans

### Multiple Builders

If using matrix builds (multiple base images, platforms):
- **Attestations per build**: 2-4 (per architecture)
- **Storage impact**: Scales with matrix size
- **Recommendation**: Keep matrix small (2-3 variants max)

## Additional Resources

- **GHCR Documentation**: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- **OCI Artifacts Spec**: https://github.com/opencontainers/artifacts
- **Sigstore Docs**: https://docs.sigstore.dev/
- **GitHub API Limits**: https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting

## Support

For GHCR-specific issues:
- **GitHub Support**: https://support.github.com/
- **GHCR Status**: https://www.githubstatus.com/
- **Community Forum**: https://github.com/orgs/community/discussions/categories/packages
