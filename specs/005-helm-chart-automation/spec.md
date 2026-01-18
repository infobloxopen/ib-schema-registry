# Feature Specification: Automated Helm Chart Publishing with Version Sync

**Feature Branch**: `005-helm-chart-automation`  
**Created**: January 17, 2026  
**Status**: Draft  
**Input**: User description: "Automated Helm Chart Publishing with Version Sync - Enable automatic publishing of the Helm chart to GitHub Container Registry (GHCR) as an OCI artifact in the CI/CD workflow, with chart versions synchronized to Docker image versions"

## Problem Statement *(mandatory)*

The Helm chart for `ib-schema-registry` is currently manually packaged and published, requiring developers to remember to update `Chart.yaml` versions and manually run `helm push` commands. This manual process creates several problems:

1. **Version Drift**: Chart versions can become out-of-sync with Docker image versions, causing confusion about which chart version corresponds to which application version
2. **Manual Toil**: Developers must remember to publish charts after every release, which is error-prone and time-consuming
3. **Inconsistent Publishing**: Charts may not be published for all image releases, leaving gaps in available versions
4. **Deployment Friction**: Users cannot rely on consistent version numbering when deploying via Helm

This feature automates the chart publishing process in the CI/CD pipeline, ensuring every Docker image build has a corresponding Helm chart with synchronized version numbers, eliminating manual steps and version inconsistencies.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automated Chart Publishing on Git Tag (Priority: P1)

When a developer pushes a git tag (e.g., `v1.2.3`), the CI/CD workflow automatically publishes both the Docker image and the Helm chart to GHCR with synchronized versions.

**Why this priority**: This is the primary release workflow for production deployments. Ensuring chart availability for every tagged release is critical for users to deploy via Helm.

**Independent Test**: Push a git tag `v1.2.3` to the repository and verify that both `ghcr.io/infobloxopen/ib-schema-registry:1.2.3` (Docker image) and `oci://ghcr.io/infobloxopen/ib-schema-registry:1.2.3` (Helm chart) are published and installable.

**Acceptance Scenarios**:

1. **Given** a developer has pushed git tag `v1.2.3`, **When** the CI/CD workflow completes, **Then** a Helm chart with version `1.2.3` is published to `oci://ghcr.io/infobloxopen/ib-schema-registry`
2. **Given** the workflow has published chart version `1.2.3`, **When** a user runs `helm pull oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3`, **Then** the chart downloads successfully
3. **Given** the chart is published, **When** a user inspects the downloaded chart, **Then** `Chart.yaml` shows `version: 1.2.3` and `appVersion: "1.2.3"` matching the Docker image tag
4. **Given** the chart version `1.2.3` exists, **When** a user runs `helm install test-sr oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3`, **Then** the application deploys successfully using the `1.2.3` Docker image

---

### User Story 2 - Automated Chart Publishing on Branch Push (Priority: P2)

When a developer pushes commits to the main branch, the CI/CD workflow automatically publishes development versions of both the Docker image and Helm chart with pre-release version numbers.

**Why this priority**: Enables continuous deployment and testing of development builds. Users can test unreleased features by deploying development versions via Helm.

**Independent Test**: Push a commit to the main branch and verify that a Helm chart with version `0.0.0-main.<short-sha>` is published alongside the Docker image `sha-<short-sha>`.

**Acceptance Scenarios**:

1. **Given** a developer has pushed commit `abc1234567` to main branch, **When** the CI/CD workflow completes, **Then** a Helm chart with version `0.0.0-main.abc1234` (using 7-char short SHA) is published
2. **Given** the development chart is published, **When** a user runs `helm install test-sr oci://ghcr.io/infobloxopen/ib-schema-registry --version 0.0.0-main.abc1234`, **Then** the application deploys using the development Docker image `sha-abc1234`
3. **Given** a development build, **When** the workflow generates the chart, **Then** both `version` and `appVersion` fields in `Chart.yaml` reflect the development version format

---

### User Story 3 - No Chart Publishing on Pull Requests (Priority: P3)

When a developer creates a pull request, the CI/CD workflow builds Docker images but does NOT publish Helm charts, preventing clutter in the registry with potentially unstable PR builds.

**Why this priority**: Reduces registry storage costs and prevents confusion from having charts for every PR build. PR builds are for testing only, not for deployment.

**Independent Test**: Create a pull request and verify that the workflow completes successfully without attempting to push a Helm chart to the registry.

**Acceptance Scenarios**:

1. **Given** a developer has created a pull request, **When** the CI/CD workflow runs, **Then** the Helm chart packaging and publishing steps are skipped entirely
2. **Given** the PR workflow completes, **When** checking the GHCR registry, **Then** no new chart versions appear for the PR commit
3. **Given** the PR build, **When** reviewing workflow logs, **Then** the logs show "Skipping chart publishing for pull request" (or similar message)

---

### Edge Cases

- **What happens when chart publishing fails but Docker image succeeds?** The workflow step should log the error clearly but not fail the entire build. Chart publishing is supplementary to the primary Docker image artifact.
- **What happens when the version format from metadata-action is unexpected?** The workflow should validate the version format and log a warning if it doesn't match semver or expected patterns, but still attempt to publish.
- **What happens if the GHCR token lacks permissions to push Helm charts?** The workflow should fail with a clear error message indicating insufficient permissions, specifically mentioning `packages:write` scope requirement.
- **What happens when re-running the workflow for the same tag?** Helm push to OCI registries typically allows overwriting. The workflow should complete successfully if pushing the same version again.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The CI/CD workflow MUST automatically package the Helm chart when building on push events (not pull requests)
- **FR-002**: The workflow MUST extract the version from the metadata action output (`steps.meta.outputs.version`)
- **FR-003**: The workflow MUST dynamically update the `version` field in `Chart.yaml` with the extracted version at build time (not committed to git)
- **FR-004**: The workflow MUST dynamically update the `appVersion` field in `Chart.yaml` to match the Docker image tag at build time
- **FR-005**: For git tags in format `v1.2.3`, the chart version MUST be `1.2.3` (strip the `v` prefix)
- **FR-006**: For branch builds (e.g., main), the chart version MUST follow the pre-release format `0.0.0-<branch>.<short-sha>` where short-sha is 7 characters
- **FR-007**: The workflow MUST push the packaged chart to `oci://ghcr.io/infobloxopen/ib-schema-registry` using the GITHUB_TOKEN
- **FR-008**: The workflow MUST log the complete chart reference (e.g., `oci://ghcr.io/infobloxopen/ib-schema-registry:1.2.3`) after successful publishing
- **FR-009**: The chart publishing step MUST run after SBOM attestation steps and before the test job in the workflow
- **FR-010**: The chart publishing step MUST be conditional on `github.event_name == 'push'` to exclude pull requests
- **FR-011**: The workflow MUST authenticate to GHCR using `helm registry login` with the GITHUB_TOKEN before pushing charts
- **FR-012**: Chart versions MUST be synchronized with Docker image versions to ensure deployment consistency

### Security & Portability Requirements

- **SPR-001**: Chart publishing MUST use the repository's `GITHUB_TOKEN` secret, not personal access tokens
- **SPR-002**: GITHUB_TOKEN MUST have `packages:write` permission scope for pushing to GHCR
- **SPR-003**: Helm registry authentication credentials MUST NOT be logged or exposed in workflow output
- **SPR-004**: The chart OCI artifact MUST coexist with Docker image artifacts at the same repository path (`ghcr.io/infobloxopen/ib-schema-registry`) using different OCI media types

### Key Entities

- **Helm Chart Package**: The packaged `.tgz` artifact containing Kubernetes manifests, `Chart.yaml`, `values.yaml`, and templates
  - Attributes: version (semver or pre-release), appVersion (matching Docker image tag), name (`ib-schema-registry`)
  - Relationships: Corresponds 1:1 with Docker image builds in the CI/CD workflow

- **Chart.yaml Metadata**: The chart descriptor file containing version metadata
  - Attributes: `version` (chart version), `appVersion` (application/Docker image version), `name`, `description`
  - Constraints: `version` and `appVersion` must be synchronized at build time, changes are build-time only (not committed)

- **OCI Registry Artifact**: The published chart in GHCR as an OCI artifact
  - Attributes: Media type (`application/vnd.cncf.helm.chart.content.v1.tar+gzip`), digest, tag (version)
  - Relationships: Stored at same repository path as Docker images but distinguished by media type

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every git tag push results in a Helm chart published to GHCR with the corresponding version within 5 minutes of workflow completion
- **SC-002**: Chart versions exactly match Docker image versions for 100% of builds (e.g., git tag `v1.2.3` produces chart version `1.2.3` and image tag `1.2.3`)
- **SC-003**: Users can successfully install the application using `helm install oci://ghcr.io/infobloxopen/ib-schema-registry --version X.Y.Z` for any published version
- **SC-004**: Development builds on main branch produce chart versions in pre-release format `0.0.0-main.<short-sha>` matching the Docker image tag `sha-<short-sha>`
- **SC-005**: Pull request builds do not publish charts to the registry (0 chart artifacts from PR builds)
- **SC-006**: Workflow execution time increases by no more than 30 seconds due to chart packaging and publishing steps
- **SC-007**: Chart publishing succeeds on first attempt for 95% of builds (allowing for transient registry issues)

## Dependencies

- **GitHub Actions Workflow**: Existing `.github/workflows/build-image.yml` file with metadata-action already configured
- **docker/metadata-action@v5**: Provides version extraction via `steps.meta.outputs.version` for Docker tags and labels
- **Helm CLI**: Must be available in the GitHub Actions runner environment (helm version 3.8+ for OCI support)
- **GitHub Container Registry (GHCR)**: OCI-compliant registry at `ghcr.io/infobloxopen/ib-schema-registry` with appropriate permissions
- **GITHUB_TOKEN Secret**: Automatic token with `packages:write` permission scope for pushing to GHCR
- **Existing Helm Chart**: `helm/ib-schema-registry/` directory with valid `Chart.yaml`, `values.yaml`, and templates

## Assumptions

- The metadata-action is already configured in the workflow and produces appropriate version strings (semantic versions from tags, branch names from branch builds)
- The GITHUB_TOKEN provided to workflows automatically has `packages:write` permission for GHCR in the repository
- Helm CLI tools are available in the GitHub Actions runner (ubuntu-latest runner includes Helm)
- The OCI registry path `ghcr.io/infobloxopen/ib-schema-registry` is accessible and can host both Docker images and Helm charts using media type differentiation
- For branch builds, the metadata-action produces output that includes the branch name and short SHA (this may need verification or custom formatting)
- Chart.yaml version updates are acceptable as build-time only modifications and do not need to be committed back to the repository
- Users are familiar with OCI-based Helm chart installation syntax (`helm install ... oci://...`)

## Out of Scope

- **Chart provenance/signing**: SLSA attestations for Helm charts are not included in this feature (future enhancement)
- **Chart version validation**: Verifying that chart versions conform to strict semver is not enforced beyond what metadata-action provides
- **Chart testing in CI**: Running `helm test` or Kubernetes deployment validation before publishing is handled separately (existing e2e tests)
- **Chart repository index**: This uses OCI artifacts, not traditional Helm repository index.yaml files
- **Multi-repository publishing**: Publishing to registries other than GHCR (e.g., Docker Hub, Artifact Registry) is not included
- **Rollback mechanism**: Automated rollback or deletion of published charts on workflow failure is not implemented
- **Version bumping automation**: Automated semantic version bumping based on commit messages (e.g., conventional commits) is not included
- **Chart changelog generation**: Automated CHANGELOG updates for chart versions are not in scope
