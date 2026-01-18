# Data Model: Automated Helm Chart Publishing with Version Sync

**Feature**: 005-helm-chart-automation  
**Date**: January 17, 2026  
**Context**: This document defines the entities, attributes, and relationships for automated Helm chart publishing.

---

## Entity Definitions

### 1. HelmChartPackage

**Description**: The packaged `.tgz` artifact containing Kubernetes manifests, metadata, and templates for deploying the Schema Registry.

**Attributes**:
- `filename`: string (format: `ib-schema-registry-<version>.tgz`, e.g., `ib-schema-registry-1.2.3.tgz`)
- `version`: string (semver format: `MAJOR.MINOR.PATCH` or pre-release: `0.0.0-<branch>.<short-sha>`)
- `appVersion`: string (matches Docker image tag, e.g., `1.2.3`, `sha-abc1234`, `main`)
- `name`: string (constant: `ib-schema-registry`)
- `created_at`: timestamp (workflow execution time)
- `size_bytes`: integer (typically 5-15 KB for chart tarball)

**Relationships**:
- **Corresponds to** exactly one `DockerImageBuild` (1:1 relationship)
- **Published to** exactly one `OCIRegistryArtifact` (1:1 relationship)
- **Derived from** `ChartYamlMetadata` (composition: chart package contains Chart.yaml)

**Lifecycle**:
1. Created: `helm package` command execution
2. Published: `helm push` to GHCR OCI registry
3. Available: Immediately after successful push (no index generation delay)
4. Immutable: Once pushed with a version tag, cannot be modified (must push new version)

**Validation Rules**:
- `version` MUST be valid semver (enforced by Helm CLI during packaging)
- `filename` MUST match pattern `<name>-<version>.tgz`
- `appVersion` MUST match the Docker image tag from the same CI/CD run
- Package MUST contain at minimum: `Chart.yaml`, `values.yaml`, `templates/` directory

---

### 2. ChartYamlMetadata

**Description**: The YAML descriptor file within the Helm chart containing version metadata and chart information.

**Attributes**:
- `version`: string (chart version, semver format)
- `appVersion`: string (application/Docker image version, quoted string)
- `name`: string (constant: `ib-schema-registry`)
- `description`: string (constant: "Confluent Schema Registry Helm Chart")
- `apiVersion`: string (constant: `v2`, Helm 3 format)
- `type`: string (constant: `application`)

**Relationships**:
- **Contained within** `HelmChartPackage` (composition)
- **Updated at build time** by workflow (not committed to git)
- **Source of truth** for chart version after dynamic update

**State Transitions**:
```
1. Git Repository State: version=0.1.0 (static placeholder)
   ↓
2. Workflow Checkout: version=0.1.0 (unchanged)
   ↓
3. sed Replacement: version=<extracted-version> (e.g., 1.2.3)
   ↓
4. helm package: Chart.yaml with updated version packaged into .tgz
   ↓
5. Workflow End: Git working directory discarded (not committed)
```

**Validation Rules**:
- `version` field MUST exist and be parseable as semver
- `appVersion` field MUST exist (Helm validates presence, not format)
- Both fields MUST be on their own line starting with field name (required for `sed` pattern matching)
- File MUST be valid YAML (Helm validates during packaging)

**Build-Time Modification**:
```bash
# Before (in git):
version: 0.1.0
appVersion: "0.1.0"

# After sed replacement (in workflow):
version: 1.2.3
appVersion: "1.2.3"

# Result: Chart packaged with version 1.2.3, git unchanged
```

---

### 3. OCIRegistryArtifact

**Description**: The Helm chart stored in GitHub Container Registry as an OCI artifact, coexisting with Docker images.

**Attributes**:
- `registry`: string (constant: `ghcr.io`)
- `repository`: string (constant: `infobloxopen/ib-schema-registry`)
- `tag`: string (equals `HelmChartPackage.version`, e.g., `1.2.3`)
- `digest`: string (SHA256 digest of chart artifact, format: `sha256:<64-hex-chars>`)
- `media_type`: string (constant: `application/vnd.cncf.helm.chart.content.v1.tar+gzip`)
- `pushed_at`: timestamp (GHCR registry timestamp)
- `size_bytes`: integer (same as `HelmChartPackage.size_bytes`)

**Relationships**:
- **Stores** exactly one `HelmChartPackage` (1:1 relationship)
- **Coexists with** multiple `DockerImageArtifacts` at same repository path (differentiated by `media_type`)
- **Accessed via** OCI URI: `oci://ghcr.io/infobloxopen/ib-schema-registry:<tag>`

**OCI Coexistence Model**:
```
ghcr.io/infobloxopen/ib-schema-registry
├── Docker Image (media_type: application/vnd.docker.distribution.manifest.v2+json)
│   ├── Tag: 1.2.3
│   ├── Tag: sha-abc1234
│   └── Tag: latest
└── Helm Chart (media_type: application/vnd.cncf.helm.chart.content.v1.tar+gzip)
    ├── Tag: 1.2.3
    ├── Tag: 0.0.0-main.abc1234
    └── (No latest tag for charts by convention)
```

**Access Patterns**:
- **Pull**: `helm pull oci://ghcr.io/infobloxopen/ib-schema-registry --version <tag>`
- **Install**: `helm install <release-name> oci://ghcr.io/infobloxopen/ib-schema-registry --version <tag>`
- **Push** (CI only): `helm push <chart>.tgz oci://ghcr.io/infobloxopen`

**Validation Rules**:
- `tag` MUST be unique per repository (pushing same tag overwrites previous chart)
- `digest` is immutable (computed by GHCR on push)
- Authentication required for push operations (read operations may be public depending on repository visibility)

---

### 4. DockerImageBuild

**Description**: The Docker image build from the same CI/CD workflow run that produces the Helm chart. This is the context entity representing the relationship between Docker images and Helm charts.

**Attributes**:
- `image_ref`: string (full image reference, e.g., `ghcr.io/infobloxopen/ib-schema-registry:1.2.3`)
- `digest`: string (multi-arch manifest digest, format: `sha256:<64-hex-chars>`)
- `platforms`: array of strings (e.g., `["linux/amd64", "linux/arm64"]`)
- `git_sha`: string (40-char commit SHA)
- `git_ref`: string (git tag or branch name)
- `workflow_run_id`: string (GitHub Actions run ID)
- `created_at`: timestamp (build completion time)

**Relationships**:
- **Produces** exactly one `HelmChartPackage` per workflow run (1:1 relationship)
- **Tagged by** `MetadataAction` (composition: metadata-action generates tags)
- **Version source** for `HelmChartPackage` (dependency: chart version derived from image version)

**Version Extraction**:
```
Git Tag: v1.2.3
  ↓ (metadata-action processes)
MetadataAction Output: steps.meta.outputs.version = "1.2.3"
  ↓ (used for both)
Docker Image Tag: ghcr.io/.../ib-schema-registry:1.2.3
Helm Chart Version: 1.2.3
```

**Synchronization Contract**:
- Docker image tag MUST equal Helm chart `appVersion` field
- Helm chart `version` field MUST equal Docker image version (not necessarily the tag name, but the version component)
- Both derived from same source: `steps.meta.outputs.version`

---

### 5. MetadataAction

**Description**: The `docker/metadata-action@v5` GitHub Actions step that generates Docker image metadata and serves as the single source of truth for version numbers.

**Attributes**:
- `step_id`: string (constant: `meta` in workflow)
- `version_output`: string (format depends on git event: semver for tags, branch name for branches, `sha-<short-sha>` for SHA builds)
- `tags_output`: array of strings (all generated image tags)
- `labels_output`: array of key-value pairs (OCI image labels)
- `created_output`: timestamp (ISO 8601 format)

**Relationships**:
- **Configures** `DockerImageBuild` (provides tags and labels)
- **Provides version to** `HelmChartPackage` (shared version source)
- **Executed before** both Docker build and Helm packaging (sequential dependency)

**Version Output Format**:
| Git Event | `github.ref` | `steps.meta.outputs.version` | Notes |
|-----------|--------------|------------------------------|-------|
| Tag push | `refs/tags/v1.2.3` | `1.2.3` | `v` prefix stripped by `type=semver,pattern={{version}}` |
| Branch push | `refs/heads/main` | `main` | Needs transformation to `0.0.0-main.<sha>` for Helm |
| PR | `refs/pull/123/merge` | `pr-123` | Not used (charts not published for PRs) |

**Configuration** (from build-image.yml):
```yaml
- name: Extract metadata
  id: meta
  uses: docker/metadata-action@v5
  with:
    images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
    tags: |
      type=ref,event=branch
      type=ref,event=pr
      type=semver,pattern={{version}}
      type=semver,pattern={{major}}.{{minor}}
      type=semver,pattern={{major}}
      type=sha
      type=raw,value=latest,enable={{is_default_branch}}
```

---

## Entity Relationships Diagram

```
┌─────────────────────┐
│  MetadataAction     │  (GitHub Actions step)
│  ─────────────────  │
│  - version_output   │
│  - tags_output      │
└──────────┬──────────┘
           │ provides version
           ├─────────────────────────┐
           │                         │
           ▼                         ▼
┌─────────────────────┐    ┌──────────────────────┐
│ DockerImageBuild    │    │ ChartYamlMetadata    │
│ ──────────────────  │    │ ───────────────────  │
│ - image_ref         │    │ - version (updated)  │
│ - digest            │    │ - appVersion (upd.)  │
│ - platforms         │    └──────────┬───────────┘
└──────────┬──────────┘               │ contained in
           │ produces (1:1)           │
           │                          ▼
           │              ┌─────────────────────┐
           │              │ HelmChartPackage    │
           │              │ ──────────────────  │
           └─────────────▶│ - filename          │
                          │ - version           │
                          │ - appVersion        │
                          └──────────┬──────────┘
                                     │ published to (1:1)
                                     ▼
                          ┌─────────────────────┐
                          │ OCIRegistryArtifact │
                          │ ──────────────────  │
                          │ - registry: ghcr.io │
                          │ - tag (=version)    │
                          │ - digest            │
                          │ - media_type: helm  │
                          └─────────────────────┘
                                     │ coexists with
                          ┌─────────────────────┐
                          │ DockerImageArtifact │
                          │ ──────────────────  │
                          │ - media_type: docker│
                          │ (same repo path)    │
                          └─────────────────────┘
```

---

## Data Flow: Git Tag to Published Chart

**Scenario**: Developer pushes git tag `v1.2.3`

```
1. GitHub Event: push tag v1.2.3
   ↓
2. Workflow Triggers: build-image.yml job "build"
   ↓
3. MetadataAction Executes:
   - Input: github.ref = refs/tags/v1.2.3
   - Output: steps.meta.outputs.version = "1.2.3"
   ↓
4. Docker Build:
   - Image tagged: ghcr.io/infobloxopen/ib-schema-registry:1.2.3
   - Pushed to GHCR
   ↓
5. SBOM Attestations:
   - Platform-specific SBOMs generated and attested
   ↓
6. Helm Chart Preparation:
   - Extract: VERSION="${{ steps.meta.outputs.version }}" → "1.2.3"
   - Update Chart.yaml:
       sed -i "s/^version:.*/version: 1.2.3/"
       sed -i "s/^appVersion:.*/appVersion: \"1.2.3\"/"
   ↓
7. Helm Package:
   - helm package helm/ib-schema-registry/
   - Output: ib-schema-registry-1.2.3.tgz
   ↓
8. Helm Authentication:
   - helm registry login ghcr.io (using GITHUB_TOKEN)
   ↓
9. Helm Push:
   - helm push ib-schema-registry-1.2.3.tgz oci://ghcr.io/infobloxopen
   - GHCR creates OCIRegistryArtifact:
       tag: 1.2.3
       digest: sha256:xyz...
       media_type: application/vnd.cncf.helm.chart.content.v1.tar+gzip
   ↓
10. Result:
    - Docker image available: ghcr.io/infobloxopen/ib-schema-registry:1.2.3
    - Helm chart available: oci://ghcr.io/infobloxopen/ib-schema-registry:1.2.3
    - Both share same version number: 1.2.3
```

---

## Data Constraints

### Version Synchronization Invariants

1. **Single Source of Truth**: `steps.meta.outputs.version` is the ONLY source for version numbers
2. **Exact Match for Tags**: For git tags, `HelmChartPackage.version` MUST exactly equal `DockerImageBuild.image_ref` version component
3. **No Manual Overrides**: Workflow MUST NOT allow manual version specification (prevents drift)
4. **Build-Time Only Modification**: `ChartYamlMetadata` updates MUST NOT be committed to git

### Semver Compliance

1. **Tag Versions**: MUST follow semver format `MAJOR.MINOR.PATCH` (e.g., `1.2.3`)
2. **Branch Versions**: MUST follow pre-release format `0.0.0-<identifier>` (e.g., `0.0.0-main.abc1234`)
3. **Pre-release Ordering**: Helm sorts `0.0.0-*` versions before `1.0.0` (expected behavior for development builds)

### OCI Registry Constraints

1. **Immutable Tags**: Once pushed, an OCI artifact with tag `X.Y.Z` cannot be modified (must push new version)
2. **Media Type Isolation**: Docker images and Helm charts at same path MUST have different media types
3. **Authentication Scope**: `GITHUB_TOKEN` MUST have `packages:write` permission for push operations

---

## Query Patterns

### User: Install Specific Version
```bash
helm install my-registry oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3
# Resolves: OCIRegistryArtifact(tag=1.2.3, media_type=helm) → HelmChartPackage
```

### User: List Available Chart Versions
```bash
# Not directly supported by Helm OCI; requires GHCR API query or container registry UI
# Alternative: Document available versions in CHANGELOG or GitHub Releases
```

### CI: Publish Chart
```bash
VERSION="1.2.3"  # From steps.meta.outputs.version
helm package helm/ib-schema-registry/  # Creates HelmChartPackage
helm push ib-schema-registry-${VERSION}.tgz oci://ghcr.io/infobloxopen  # Creates OCIRegistryArtifact
```

### Developer: Verify Version Sync
```bash
# Check Docker image version:
docker inspect ghcr.io/infobloxopen/ib-schema-registry:1.2.3 | jq '.[0].Config.Labels."org.opencontainers.image.version"'

# Check Helm chart version:
helm pull oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3
tar -xzf ib-schema-registry-1.2.3.tgz
grep "^version:" ib-schema-registry/Chart.yaml
grep "^appVersion:" ib-schema-registry/Chart.yaml

# Expected: All three outputs should be "1.2.3"
```

---

## Summary

This data model defines 5 core entities and their relationships for automated Helm chart publishing:

1. **MetadataAction**: Single source of truth for version numbers
2. **ChartYamlMetadata**: Dynamically updated at build time (not committed)
3. **HelmChartPackage**: Packaged chart artifact (.tgz)
4. **OCIRegistryArtifact**: Chart stored in GHCR with Helm media type
5. **DockerImageBuild**: Related Docker image from same workflow run

Key design principles:
- **Version synchronization** via shared metadata-action output
- **Build-time Chart.yaml updates** keep git history clean
- **OCI coexistence** enables single repository path for all artifacts
- **Immutable artifacts** ensure reproducibility and audit trails
