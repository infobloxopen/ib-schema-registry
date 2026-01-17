# SLSA Provenance Research

**Date**: 2025-01-17  
**Feature**: SLSA Provenance Attestation  
**Tasks**: T001, T002, T003

## T001: Docker Buildx Provenance Capabilities

### Overview
Docker buildx (BuildKit) has native support for generating SLSA provenance attestations starting from BuildKit v0.11+. The provenance is automatically generated during the build process and attached as an OCI attestation manifest.

### Key Capabilities

1. **Built-in Provenance Generation**
   - Enabled via `--provenance` flag or `provenance` parameter in build-push-action
   - Generates SLSA Provenance v0.2 or v1.0 format
   - No additional tools required

2. **Provenance Modes**
   - `mode=min`: Minimal provenance (default when enabled)
   - `mode=max`: Maximum detail including build arguments, secrets references (not values), and full build context

3. **Multi-Architecture Support**
   - Each architecture in a multi-platform build gets its own attestation
   - Attestations are attached to architecture-specific image digests
   - Manifest list references all attestations

4. **Content Included**
   - Build invocation (builder, build arguments)
   - Source materials (context, Dockerfile location)
   - Build metadata (timestamp, build duration)
   - Builder environment (BuildKit version, platform)

### Implementation with docker/build-push-action@v5

```yaml
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    context: .
    platforms: linux/amd64,linux/arm64
    push: true
    provenance: mode=max  # Enable provenance with maximum detail
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
    build-args: |
      VERSION=${{ steps.version.outputs.local_version }}
      REVISION=${{ github.sha }}
      CREATED=${{ steps.meta.outputs.created }}
      SOURCE_REPOSITORY=${{ github.repositoryUrl }}
      SOURCE_COMMIT=${{ github.sha }}
      BUILD_WORKFLOW=${{ github.workflow }}@${{ github.ref }}
```

### SLSA Attestation Format

The provenance follows the SLSA Provenance schema with these key sections:

- **Predicate Type**: `https://slsa.dev/provenance/v1.0`
- **Subject**: Image digest and architecture
- **Builder**: BuildKit builder identity
- **Invocation**: Build command and parameters
- **Materials**: Source repository, Dockerfile, base images
- **Metadata**: Build timestamps, completeness guarantees

### Storage and Retrieval

- Attestations are stored in the OCI registry as separate manifest layers
- Referenced via OCI Image Index (manifest list)
- Can be queried using:
  - `docker buildx imagetools inspect <image> --format '{{json .Provenance}}'`
  - `cosign verify-attestation <image>`
  - `slsa-verifier verify-image <image>`

## T002: GitHub Actions OIDC Token Provider

### Overview
GitHub Actions provides an OIDC token that can be used for keyless signing of attestations. This eliminates the need to manage signing keys or secrets.

### Key Features

1. **Automatic Token Generation**
   - GitHub automatically generates short-lived OIDC tokens for workflow runs
   - Token includes claims about the workflow identity (repo, ref, workflow, etc.)
   - No secret management required

2. **Required Permissions**
   ```yaml
   permissions:
     id-token: write  # Required for OIDC token generation
     packages: write  # Required for pushing images and attestations
     contents: read   # Required for checking out code
   ```

3. **Token Claims**
   The OIDC token includes:
   - `repository`: GitHub repository (owner/repo)
   - `ref`: Git ref that triggered the workflow
   - `workflow`: Workflow file name
   - `sha`: Git commit SHA
   - `actor`: User who triggered the workflow
   - `repository_owner`: Repository owner

4. **Signature Verification**
   - Signatures can be verified using Sigstore's public-good infrastructure
   - No need for consumers to have access to private keys
   - Trust chain: GitHub OIDC → Fulcio CA → Rekor transparency log

### Integration with BuildKit

BuildKit can automatically use the GitHub OIDC token when:
1. Running in GitHub Actions with `id-token: write` permission
2. BuildKit detects the GitHub Actions environment
3. Provenance generation is enabled

The signature is created using:
- **Signer**: GitHub Actions OIDC identity
- **Certificate**: Issued by Sigstore Fulcio CA
- **Transparency**: Logged in Sigstore Rekor
- **Format**: Cosign-compatible signature

### No Additional Configuration Required

When using docker/build-push-action@v5 in GitHub Actions:
- BuildKit automatically detects GitHub OIDC availability
- Attestations are signed using the OIDC token
- No cosign or sigstore-specific actions needed

## T003: Provenance Verification Workflows

### Verification Tools

#### 1. Docker Buildx Imagetools
**Best for**: Quick inspection of provenance content

```bash
# Inspect image provenance
docker buildx imagetools inspect \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --format '{{json .Provenance}}'

# View attestation for specific architecture
docker buildx imagetools inspect \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --format '{{json .Provenance}}' \
  --platform linux/amd64
```

**Advantages**:
- Built into Docker toolchain
- No additional tool installation
- Works offline if image is pulled

**Limitations**:
- Doesn't verify signatures
- Doesn't validate SLSA compliance

#### 2. Cosign
**Best for**: Signature verification and attestation validation

```bash
# Verify attestation signature (keyless)
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest

# Download and inspect attestation
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  | jq '.payload | @base64d | fromjson'
```

**Advantages**:
- Cryptographic signature verification
- Validates GitHub OIDC identity
- Standard tool for container signing

**Limitations**:
- Requires internet access for Sigstore Rekor
- Doesn't validate SLSA-specific requirements

#### 3. SLSA Verifier
**Best for**: SLSA compliance validation

```bash
# Verify image against SLSA requirements
slsa-verifier verify-image \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --source-uri github.com/infobloxopen/ib-schema-registry \
  --source-tag v1.0.0

# Verify with specific builder
slsa-verifier verify-image \
  ghcr.io/infobloxopen/ib-schema-registry:latest \
  --source-uri github.com/infobloxopen/ib-schema-registry \
  --builder-id https://github.com/docker/build-push-action/.github/workflows/build.yml
```

**Advantages**:
- Validates SLSA provenance schema
- Checks source repository matches
- Verifies builder identity
- Enforces SLSA level requirements

**Limitations**:
- Separate tool installation required
- Less flexible for custom attestation inspection

### Multi-Architecture Verification

For multi-arch images, verify each architecture separately:

```bash
# List all architectures
docker buildx imagetools inspect ghcr.io/infobloxopen/ib-schema-registry:latest

# Verify amd64
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest@sha256:amd64_digest_here

# Verify arm64
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:latest@sha256:arm64_digest_here
```

### Offline/Air-Gapped Verification

For environments without internet access:

1. **Pre-download public keys and certificates**:
   ```bash
   # Download Sigstore root of trust
   cosign initialize
   
   # Download Rekor public key
   wget https://rekor.sigstore.dev/api/v1/log/publicKey -O rekor-pubkey.pem
   ```

2. **Export attestations before air-gap**:
   ```bash
   # Export image with attestations
   docker pull ghcr.io/infobloxopen/ib-schema-registry:latest
   docker save ghcr.io/infobloxopen/ib-schema-registry:latest > image.tar
   
   # Export attestations separately
   cosign download attestation ghcr.io/infobloxopen/ib-schema-registry:latest > attestation.json
   ```

3. **Verify in air-gapped environment**:
   ```bash
   # Load image
   docker load < image.tar
   
   # Verify using local Rekor data
   cosign verify-attestation \
     --offline \
     --type slsaprovenance \
     --local-image \
     ghcr.io/infobloxopen/ib-schema-registry:latest
   ```

### Recommended Verification Workflow

1. **Quick Check** (Docker buildx):
   - Verify provenance exists
   - Inspect basic metadata

2. **Signature Verification** (Cosign):
   - Validate cryptographic signature
   - Verify GitHub OIDC identity
   - Check source repository

3. **SLSA Compliance** (slsa-verifier):
   - Validate SLSA schema
   - Verify source matches expected repository
   - Check builder identity

### Integration into CI/CD

Add verification as a post-deployment check:

```yaml
- name: Verify provenance
  run: |
    # Install tools
    go install github.com/sigstore/cosign/v2/cmd/cosign@latest
    go install github.com/slsa-framework/slsa-verifier/v2/cli/slsa-verifier@latest
    
    # Verify signature
    cosign verify-attestation \
      --type slsaprovenance \
      --certificate-identity-regexp '^https://github.com/${{ github.repository }}/' \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
    
    # Verify SLSA compliance
    slsa-verifier verify-image \
      ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
      --source-uri github.com/${{ github.repository }}
```

## Summary

- **T001**: Docker buildx has native SLSA provenance support via `provenance: mode=max` parameter
- **T002**: GitHub Actions OIDC tokens enable keyless signing with no secret management
- **T003**: Verification workflow uses docker buildx (inspection), cosign (signature), and slsa-verifier (SLSA compliance)

## Next Steps

Phase 2 (Foundational):
- Add `id-token: write` permission to build job
- Enable `provenance: mode=max` in build-push-action
- Add build-args for SLSA metadata (source URL, commit SHA, workflow ref)
- Test provenance generation locally
