# Helm Chart Provenance Verification Guide

**Purpose**: Guide for verifying SLSA provenance attestations on Helm charts (when OCI publishing is enabled)  
**Date**: 2025-01-17  
**Status**: Documentation ready for when Helm chart OCI publishing is activated  
**Audience**: Kubernetes administrators, platform engineers

## Overview

> **Note**: Helm chart publishing to OCI registries is currently disabled. This guide documents the provenance verification workflow for when OCI publishing is activated in the future.

When enabled, Helm charts published to OCI registries will include SLSA provenance attestations similar to container images. These attestations provide verifiable metadata about:

- **Chart Source**: Repository URL and commit SHA
- **Chart Version**: Semantic version from Chart.yaml
- **Build Workflow**: GitHub Actions workflow that packaged the chart
- **Build Environment**: Builder identity and platform

## Prerequisites

- **Helm 3.8+**: OCI registry support (charts stored as OCI artifacts)
- **cosign** or **slsa-verifier**: For attestation verification
- **kubectl**: For Kubernetes cluster access (optional)

## Quick Start (Future)

Once OCI publishing is enabled:

```bash
# Pull Helm chart from OCI registry
helm pull oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.0.0

# Verify chart provenance
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  oci://ghcr.io/infobloxopen/ib-schema-registry:1.0.0
```

## Helm OCI Registry Support

### What is Helm OCI Support?

Helm 3.8+ can store charts as OCI artifacts in container registries (GHCR, Docker Hub, etc.). This enables:

- **Unified storage**: Charts and images in the same registry
- **Provenance attestations**: Charts can have SLSA attestations like images
- **Signature verification**: Cryptographically verify chart authenticity
- **Access control**: Use registry permissions for charts

### Enabling OCI Publishing

To enable Helm chart publishing (currently commented out in `.github/workflows/helm-test.yaml`):

1. **Uncomment the publish job** in `helm-test.yaml`
2. **Add provenance generation** to the Helm packaging step
3. **Configure OIDC signing** for chart attestations

Example workflow (future implementation):

```yaml
publish:
  name: Publish Helm Chart with Provenance
  runs-on: ubuntu-latest
  permissions:
    id-token: write  # Required for OIDC signing
    packages: write  # Required for GHCR push
    contents: read
  steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Helm
      uses: azure/setup-helm@v3
      with:
        version: '3.13.0'

    - name: Login to GHCR
      run: |
        echo "${{ secrets.GITHUB_TOKEN }}" | \
        helm registry login ghcr.io -u ${{ github.actor }} --password-stdin

    - name: Package and push chart with provenance
      run: |
        CHART_VERSION=$(grep '^version:' helm/ib-schema-registry/Chart.yaml | awk '{print $2}')
        
        # Package chart
        helm package helm/ib-schema-registry/ --version "$CHART_VERSION"
        
        # Push to OCI registry
        helm push ib-schema-registry-${CHART_VERSION}.tgz \
          oci://ghcr.io/${{ github.repository_owner }}

    - name: Generate and attach provenance
      run: |
        # Generate SLSA provenance for Helm chart
        # This would use a tool like slsa-provenance-action or custom script
        # to generate attestation and attach it to the OCI artifact
        echo "Provenance generation for Helm charts TBD"
```

## Verification Methods

### Option 1: Cosign (Recommended)

Once charts are published with provenance:

```bash
# Verify Helm chart provenance signature
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  oci://ghcr.io/infobloxopen/ib-schema-registry:1.0.0

# Extract provenance content
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  oci://ghcr.io/infobloxopen/ib-schema-registry:1.0.0 \
  | jq -r '.payload | @base64d | fromjson | .predicate'
```

### Option 2: SLSA Verifier

```bash
# Verify chart against source repository
slsa-verifier verify-artifact \
  oci://ghcr.io/infobloxopen/ib-schema-registry:1.0.0 \
  --source-uri github.com/infobloxopen/ib-schema-registry \
  --source-tag v1.0.0
```

### Option 3: OCI Registry Tools

```bash
# Inspect OCI artifact in registry
oras discover oci://ghcr.io/infobloxopen/ib-schema-registry:1.0.0

# Pull attestation manifest
oras pull oci://ghcr.io/infobloxopen/ib-schema-registry:1.0.0 \
  --media-type application/vnd.in-toto+json
```

## Expected Provenance Content

A Helm chart provenance attestation should include:

```json
{
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "builder": {
      "id": "https://github.com/helm/chart-releaser-action@v1"
    },
    "buildType": "https://helm.sh/chart-package@v1",
    "invocation": {
      "configSource": {
        "uri": "https://github.com/infobloxopen/ib-schema-registry",
        "digest": {
          "sha1": "<commit-sha>"
        }
      },
      "parameters": {
        "chartPath": "helm/ib-schema-registry",
        "chartVersion": "1.0.0"
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
        "uri": "pkg:helm/ib-schema-registry@1.0.0",
        "digest": {
          "sha256": "<chart-digest>"
        }
      }
    ],
    "metadata": {
      "buildStartedOn": "2025-01-17T...",
      "buildFinishedOn": "2025-01-17T...",
      "completeness": {
        "parameters": true,
        "environment": false,
        "materials": true
      }
    }
  }
}
```

### Key Fields

- **builder.id**: Helm chart releaser or GitHub Actions workflow
- **invocation.configSource.uri**: Chart source repository
- **invocation.parameters.chartVersion**: Chart version from Chart.yaml
- **materials**: Source repository, chart files, dependencies

## Verification Scenarios

### Scenario 1: Pre-Deployment Verification

Before deploying a Helm chart to production:

```bash
#!/bin/bash
# Pre-deployment verification script

CHART_REF="oci://ghcr.io/infobloxopen/ib-schema-registry:1.0.0"
REQUIRED_SOURCE="github.com/infobloxopen/ib-schema-registry"
REQUIRED_VERSION="1.0.0"

echo "Verifying Helm chart: $CHART_REF"

# Verify provenance
if cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$CHART_REF" > /dev/null 2>&1; then
  echo "✅ Provenance signature verified"
else
  echo "❌ Provenance verification failed"
  exit 1
fi

# Extract and validate metadata
CHART_VERSION=$(cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$CHART_REF" \
  | jq -r '.payload | @base64d | fromjson | .predicate.invocation.parameters.chartVersion')

if [ "$CHART_VERSION" = "$REQUIRED_VERSION" ]; then
  echo "✅ Chart version matches: $CHART_VERSION"
else
  echo "❌ Chart version mismatch: expected $REQUIRED_VERSION, got $CHART_VERSION"
  exit 1
fi

echo "✅ All checks passed - safe to deploy"
```

### Scenario 2: Audit Trail

Generate audit report for compliance:

```bash
#!/bin/bash
# Helm chart audit report

CHART_REF="oci://ghcr.io/infobloxopen/ib-schema-registry:1.0.0"
OUTPUT_FILE="helm-chart-audit-$(date +%Y%m%d).json"

echo "Generating audit report for $CHART_REF..."

cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$CHART_REF" \
  | jq '{
      auditTimestamp: now | todate,
      chartReference: "'$CHART_REF'",
      verificationStatus: "PASSED",
      provenance: (.payload | @base64d | fromjson | .predicate | {
        source: .invocation.configSource.uri,
        commit: .invocation.configSource.digest.sha1,
        chartVersion: .invocation.parameters.chartVersion,
        buildTime: .metadata.buildStartedOn,
        builder: .builder.id
      })
    }' > "$OUTPUT_FILE"

echo "✅ Audit report saved to $OUTPUT_FILE"
```

### Scenario 3: CI/CD Pipeline Integration

Integrate verification into your deployment pipeline:

```yaml
# Example: GitLab CI, Jenkins, Tekton, etc.
verify-helm-chart:
  stage: verify
  script:
    - |
      # Install cosign
      curl -sL https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 -o /usr/local/bin/cosign
      chmod +x /usr/local/bin/cosign
      
      # Verify chart provenance
      cosign verify-attestation \
        --type slsaprovenance \
        --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
        --certificate-oidc-issuer https://token.actions.githubusercontent.com \
        oci://ghcr.io/infobloxopen/ib-schema-registry:${CHART_VERSION}
      
      # Deploy if verification succeeds
      helm upgrade --install schema-registry \
        oci://ghcr.io/infobloxopen/ib-schema-registry \
        --version ${CHART_VERSION}
```

## Current State (Without OCI Publishing)

Currently, Helm charts are packaged but not published to OCI registries. Users install charts via:

1. **Local installation**:
   ```bash
   helm install schema-registry ./helm/ib-schema-registry
   ```

2. **Git repository installation**:
   ```bash
   git clone https://github.com/infobloxopen/ib-schema-registry.git
   helm install schema-registry ./ib-schema-registry/helm/ib-schema-registry
   ```

**Provenance verification for these installation methods**:

Since charts are not published to OCI registries, provenance verification is achieved by:

1. **Verify source repository** (git commit signatures):
   ```bash
   git log --show-signature -1
   ```

2. **Verify container images used by chart**:
   ```bash
   # Extract image reference from values.yaml
   IMAGE=$(yq '.image.repository' helm/ib-schema-registry/values.yaml)
   TAG=$(yq '.image.tag' helm/ib-schema-registry/values.yaml)
   
   # Verify image provenance
   cosign verify-attestation \
     --type slsaprovenance \
     --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
     ${IMAGE}:${TAG}
   ```

3. **Verify chart integrity** (Helm built-in):
   ```bash
   helm lint ./helm/ib-schema-registry
   helm template schema-registry ./helm/ib-schema-registry --validate
   ```

## Roadmap

To enable full Helm chart provenance:

1. **Phase 1**: Enable OCI registry publishing (uncomment publish job)
2. **Phase 2**: Add provenance generation to Helm packaging
3. **Phase 3**: Sign chart attestations with GitHub OIDC
4. **Phase 4**: Add provenance verification to helm-e2e tests
5. **Phase 5**: Document consumer verification workflows

## Additional Resources

- **Helm OCI Support**: https://helm.sh/docs/topics/registries/
- **SLSA for Package Managers**: https://slsa.dev/spec/v1.0/requirements#package-managers
- **Cosign Artifact Signing**: https://docs.sigstore.dev/cosign/signing/other_types/
- **ORAS (OCI Registry as Storage)**: https://oras.land/

## Support

For questions about Helm chart provenance:

1. Check the [container image provenance documentation](provenance-verification.md) for similar workflows
2. Review the [CI provenance guide](ci-provenance-guide.md) for build automation patterns
3. Open an issue in the repository for Helm-specific provenance questions

---

**Note**: This guide will be updated when Helm chart OCI publishing is activated.
