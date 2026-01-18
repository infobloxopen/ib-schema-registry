# Quickstart: Idempotent SBOM Generation

**Date**: 2026-01-17  
**Purpose**: Walkthrough of the new SBOM generation feature with idempotent digest caching

## Overview

The SBOM generation system now supports **idempotent operation**: generating SBOMs multiple times for the same image digest succeeds without conflicts. The system automatically detects when an SBOM already exists, verifies it is identical, and succeeds without errors.

## Quick Start

### Prerequisites

1. **Syft installed**: SBOM generation tool
   ```bash
   make sbom-install-tools  # Installs Syft + Grype
   ```

2. **Docker image built**:
   ```bash
   make build  # Builds ib-schema-registry:latest locally
   ```

### Generate SBOM for Native Platform

```bash
make sbom TAG=latest
```

**What happens**:
- Scans the `ib-schema-registry:latest` image
- Generates two SBOMs: CycloneDX and SPDX formats
- Stores them in `build/sbom/` directory:
  - `build/sbom/latest-amd64.cyclonedx.json` (if on Apple Silicon/arm64)
  - `build/sbom/latest-amd64.spdx.json`
- Creates metadata files alongside SBOMs
- Prints success message with file paths and operation status

**Example output**:
```
→ Generating SBOM for ib-schema-registry:latest...
  Platform: linux/arm64 (auto-detected)

→ Generating CycloneDX SBOM...
✓ SBOM generated successfully
  File: build/sbom/latest-arm64.cyclonedx.json
  Size: 15K
  Components: ~450
  Metadata: build/sbom/latest-arm64.cyclonedx.metadata.json
  Operation: GENERATED
  Digest: sha256:a9f36f222baa73fd...
  Hash: sha256:b8c47e555caa84...

→ Generating SPDX SBOM...
✓ SBOM generated successfully
  File: build/sbom/latest-arm64.spdx.json
  Size: 18K
  Operation: GENERATED

✓ SBOM generation complete

Generated files:
-rw-r--r--  15K build/sbom/latest-arm64.cyclonedx.json
-rw-r--r--   2K build/sbom/latest-arm64.cyclonedx.metadata.json
-rw-r--r--  18K build/sbom/latest-arm64.spdx.json
-rw-r--r--   2K build/sbom/latest-arm64.spdx.metadata.json

Next steps:
  make sbom-validate SBOM_TAG=latest  # Validate and scan for vulnerabilities
```

---

## Idempotent Regeneration (New Feature)

### Generate SBOM Again for Same Image

Run the same command again:
```bash
make sbom TAG=latest
```

**What happens** (NEW BEHAVIOR):
- Script detects existing SBOM and metadata.json
- Regenerates SBOM from image
- Compares hash of new SBOM with stored hash
- **Since digest is identical, hashes match**: Operation reported as `VERIFIED_IDENTICAL`
- Existing SBOM file **preserved** (not overwritten)
- Metadata updated with new timestamp
- Script exits with success (0) - **NOT an error**

**Example output**:
```
→ Generating SBOM for ib-schema-registry:latest...
  Platform: linux/arm64 (auto-detected)

→ Generating CycloneDX SBOM...
✓ SBOM verified identical (no changes)
  File: build/sbom/latest-arm64.cyclonedx.json
  Size: 15K
  Operation: VERIFIED_IDENTICAL
  Digest: sha256:a9f36f222baa73fd...
  Hash: sha256:b8c47e555caa84... [unchanged]
  Last verified: 2026-01-17T10:35:22Z
```

**Key points**:
- ✅ Exit code: 0 (success, not error)
- ✅ Message clearly states "VERIFIED_IDENTICAL"
- ✅ No "cannot overwrite digest" error
- ✅ Safe to re-run in CI/CD without conflicts

---

## Update SBOM When Image Changes

### Modify Dependencies and Rebuild

```bash
# Edit Dockerfile or dependency files
# Then rebuild the image
make build TAG=latest
```

**New digest is created** (different source):
```bash
# Now run SBOM generation again
make sbom TAG=latest
```

**What happens**:
- Script regenerates SBOM from new image
- Compares hash of new SBOM with previously stored hash
- **Hashes differ** (image contents changed): Operation reported as `UPDATED`
- Existing SBOM file **replaced** with new version
- Metadata updated with new digest, hash, and timestamp
- Script exits with success (0)

**Example output**:
```
→ Generating SBOM for ib-schema-registry:latest...

→ Generating CycloneDX SBOM...
✓ SBOM updated (image changed)
  File: build/sbom/latest-arm64.cyclonedx.json
  Size: 16K (was 15K)
  Operation: UPDATED
  Digest: sha256:NEW_DIGEST_HASH...
  Hash: sha256:NEW_CONTENT_HASH... [changed]
  Components: ~455 (was ~450)
```

---

## Multi-Architecture SBOM Generation

### Generate SBOMs for Both Architectures

```bash
make sbom-multi TAG=latest
```

**What happens**:
- Builds SBOMs for both `linux/amd64` and `linux/arm64`
- Each architecture has independent SBOM artifacts:
  - `build/sbom/latest-amd64.cyclonedx.json`
  - `build/sbom/latest-arm64.cyclonedx.json`
- Metadata.json separate for each arch
- **Each architecture handled independently** for idempotency (no digest conflicts between architectures)

**Example output**:
```
→ Generating multi-architecture SBOMs for ib-schema-registry:latest...

→ Generating SBOMs for linux/amd64...
✓ SBOM generated successfully [linux/amd64]
✓ SBOM generated successfully [linux/amd64]

→ Generating SBOMs for linux/arm64...
✓ SBOM generated successfully [linux/arm64]
✓ SBOM generated successfully [linux/arm64]

Generated files:
-rw-r--r-- build/sbom/latest-amd64.cyclonedx.json
-rw-r--r-- build/sbom/latest-amd64.spdx.json
-rw-r--r-- build/sbom/latest-arm64.cyclonedx.json
-rw-r--r-- build/sbom/latest-arm64.spdx.json
```

---

## CI/CD Workflow Example

### GitHub Actions: Build and Generate SBOMs

```yaml
# In .github/workflows/build.yml
jobs:
  build-and-sbom:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build multi-arch image
        run: make buildx TAG=7.6.1
      
      - name: Generate SBOMs for all platforms
        run: make sbom-multi TAG=7.6.1
      
      - name: Push image and artifacts
        run: |
          make push TAG=7.6.1
          make sbom-validate SBOM_TAG=7.6.1
```

**Behavior**:
1. First run: SBOMs generated (`GENERATED`)
2. If CI re-runs same job (same source): SBOMs verified identical (`VERIFIED_IDENTICAL`) - ✅ no errors
3. If source changes: SBOMs updated (`UPDATED`) on next run
4. Multi-arch builds generate separate SBOMs per architecture - no conflicts

---

## Validate SBOM Quality

### Check SBOM Format and Scan for Vulnerabilities

```bash
make sbom-validate SBOM_TAG=latest
```

**What happens**:
- Validates SBOM JSON structure (CycloneDX/SPDX compliance)
- Scans components for known CVEs (requires Grype)
- Reports vulnerabilities found
- Exit code 0 if no critical CVEs, non-zero if vulnerabilities exist

**Example output**:
```
→ Validating SBOM: build/sbom/latest-amd64.cyclonedx.json

Checking JSON format...
✓ Valid CycloneDX JSON

Scanning for vulnerabilities with Grype...
✓ No critical vulnerabilities found
  - 0 Critical
  - 2 High
  - 5 Medium
  - 12 Low

Details: Use `grype sbom:build/sbom/latest-amd64.cyclonedx.json` for full report
```

---

## Metadata and Auditing

### Inspect SBOM Metadata

```bash
# View metadata for amd64 CycloneDX SBOM
cat build/sbom/latest-amd64.cyclonedx.metadata.json | jq .

# Output:
{
  "image": "ib-schema-registry:latest",
  "digest": "sha256:a9f36f222baa73fd5590d4648446f9632a2db54e3e0f601994986440f232b249",
  "platform": "linux/amd64",
  "format": "cyclonedx-json",
  "generated_at": "2026-01-17T10:30:45Z",
  "tool": "syft",
  "tool_version": "1.0.0",
  "content_hash": "sha256:b8c47e555caa84ge6691e5759557d3cf3e3fc65e5f611993988552330g343350",
  "operation": "VERIFIED_IDENTICAL",
  "file_size_bytes": 15234,
  "output_file": "build/sbom/latest-amd64.cyclonedx.json"
}
```

**Fields**:
- `digest`: Image digest (unique per architecture)
- `operation`: Last operation (GENERATED, VERIFIED_IDENTICAL, UPDATED)
- `content_hash`: Hash of SBOM file (used for idempotency check)
- `generated_at`: When SBOM was last generated/verified

---

## Troubleshooting

### "Syft is not installed"

```bash
make sbom-install-tools
```

### "Image not found locally"

Build the image first:
```bash
make build TAG=latest
```

### SBOM file seems old or unchanged

Check the metadata:
```bash
cat build/sbom/[tag]-[arch].cyclonedx.metadata.json | jq '.operation, .generated_at'
```

If operation is `VERIFIED_IDENTICAL`, the SBOM is current and verified to match the image.

### Manual cleanup of SBOMs

```bash
# Remove all SBOM artifacts
rm -rf build/sbom/

# Next run will regenerate from scratch
make sbom TAG=latest
```

