# Implementation Plan: Automated Helm Chart Publishing with Version Sync

**Branch**: `005-helm-chart-automation` | **Date**: January 17, 2026 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/005-helm-chart-automation/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Automate Helm chart publishing to GitHub Container Registry (GHCR) as OCI artifacts in the CI/CD workflow, with chart versions synchronized to Docker image versions. This eliminates manual chart publishing, prevents version drift, and ensures every Docker image build has a corresponding Helm chart with synchronized version numbers. The approach leverages the existing `docker/metadata-action` output for version extraction and dynamically updates `Chart.yaml` at build time (not committed to git).

## Technical Context

**Language/Version**: YAML (GitHub Actions workflows), Shell (bash scripting for version manipulation), Helm 3.8+ CLI  
**Primary Dependencies**: 
- `docker/metadata-action@v5` (version extraction from git tags/branches)
- `helm` CLI (OCI registry support for `helm push`)
- `sed` (Chart.yaml field updates)
- GitHub Container Registry (GHCR) OCI support

**Storage**: GHCR OCI registry at `ghcr.io/infobloxopen/ib-schema-registry` (coexists with Docker images via different media types)  
**Testing**: Manual verification (helm pull/install), CI workflow validation, existing e2e tests (Helm chart functionality already tested)  
**Target Platform**: GitHub Actions ubuntu-latest runner (already includes Helm CLI)  
**Project Type**: CI/CD automation (GitHub Actions workflow modification)  
**Performance Goals**: Chart packaging and publishing adds <30 seconds to workflow execution time  
**Constraints**: 
- Chart versions MUST exactly match Docker image versions (no drift)
- Build-time only Chart.yaml modifications (not committed)
- Conditional execution (only on push events, not PRs)
- Must not break existing multi-arch build workflow

**Scale/Scope**: Single workflow job addition, affects ~50 lines of YAML in `.github/workflows/build-image.yml`, modifies 2 fields in `Chart.yaml` dynamically

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Multi-arch portability**: This feature is CI/CD automation only (workflow YAML + shell commands). No platform-specific scripts. The `sed` commands for Chart.yaml updates are POSIX-compliant and work identically on GitHub Actions ubuntu-latest runners regardless of architecture.
- [x] **Base image pluggability**: Not applicable (this feature doesn't modify Docker images or their base images).
- [x] **Distroless compatibility**: Not applicable (this feature doesn't modify container runtime behavior).
- [x] **Supply-chain security**: 
  - [x] Runtime images run as non-root user: Not applicable (no container images modified).
  - [x] No `curl | bash` installers: Helm CLI already available in GitHub Actions runner; no additional downloads.
  - [x] Base images pinned by digest: Not applicable (no Docker builds modified).
  - [x] OCI labels included: Not applicable (this feature publishes Helm charts, which will inherit OCI metadata from the Helm package itself; Docker image OCI labels unchanged).
- [x] **Licensing compliance**: No upstream code copied. This feature adds workflow automation using existing Helm chart (already in repo under `helm/ib-schema-registry/`). No new license implications.
- [x] **Repository ergonomics**: 
  - Existing Makefile targets (`make helm-package`, `make helm-push`) remain usable for manual operations.
  - Automation complements but does not replace manual workflows.
  - Documentation will be updated in README and Helm chart README with OCI usage examples.
- [x] **Testing validation**: 
  - CI continues to build both `linux/amd64` and `linux/arm64` Docker images (unchanged).
  - Helm chart publishing step only affects artifact distribution, not image builds.
  - Smoke tests remain unchanged (Docker container startup validation).
  - Helm chart functionality already validated by existing e2e tests in `tests/e2e/test-helm-chart.sh`.

**Violations**: None. This feature is pure CI/CD automation for artifact publishing and does not modify any container images, build processes, or runtime behavior governed by the constitution. All constitution principles remain satisfied.

## Project Structure

### Documentation (this feature)

```text
specs/005-helm-chart-automation/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (version format research)
├── data-model.md        # Phase 1 output (OCI artifact structure, Chart.yaml schema)
├── quickstart.md        # Phase 1 output (how to use automated publishing)
├── contracts/           # Phase 1 output (workflow contract, version mapping)
│   ├── workflow-integration.yaml  # Pseudo-code for CI/CD steps
│   └── version-mapping.md         # Git tag → Chart version transformation rules
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

This feature modifies existing CI/CD and documentation files:

```text
.github/workflows/
└── build-image.yml      # Modified: Add Helm chart publishing step after SBOM attestations

helm/ib-schema-registry/
├── Chart.yaml           # Modified at build-time only (version + appVersion fields updated by sed)
├── values.yaml          # Unchanged
├── templates/           # Unchanged
└── README.md            # Modified: Add OCI installation instructions

README.md                # Modified: Add Helm chart OCI usage section
```

**Structure Decision**: Single-project CI/CD modification. No new source directories needed. This is an infrastructure/automation feature that extends the existing GitHub Actions workflow to publish Helm charts alongside Docker images. The Helm chart structure already exists in `helm/ib-schema-registry/` and requires no changes beyond build-time Chart.yaml field updates.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations. This section intentionally left blank.
