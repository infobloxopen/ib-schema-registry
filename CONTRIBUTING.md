# Contributing to Infoblox Schema Registry

Thank you for your interest in contributing! This document provides guidelines for developing, testing, and submitting changes to the Infoblox Schema Registry build infrastructure.

## Development Workflow

### Prerequisites

Before you begin, ensure you have:

- **Docker**: Version 20.10+ with BuildKit enabled
- **Docker Buildx**: Multi-architecture build support
- **Git**: Version 2.x+ with submodule support
- **Make**: Build automation
- **Shell**: Bash 4.0+ for test scripts

### Setting Up Development Environment

```bash
# Fork and clone repository
git clone --recurse-submodules https://github.com/YOUR_USERNAME/ib-schema-registry.git
cd ib-schema-registry

# Verify prerequisites
make info

# Initialize submodule (if not cloned with --recurse-submodules)
make submodule-init

# Build image
make build

# Run tests
make test

# Generate and validate SBOM
make sbom
make sbom-validate
```

### Project Structure

```
.
├── Dockerfile                  # Multi-stage build definition
├── Makefile                    # Build automation
├── LICENSE.md                  # Licensing and compliance
├── README.md                   # User-facing documentation
├── CONTRIBUTING.md             # This file
├── config/
│   └── schema-registry.properties  # Default configuration
├── scripts/
│   └── sbom/                   # SBOM generation scripts
│       ├── generate-sbom.sh    # Generate SBOM for image
│       └── validate-sbom.sh    # Validate SBOM format
├── build/
│   └── sbom/                   # Generated SBOM files (gitignored)
│       └── README.md           # SBOM documentation
├── .github/
│   └── workflows/
│       └── build-image.yml     # CI/CD pipeline
├── upstream/
│   └── schema-registry/        # Git submodule (Confluent source)
├── tests/
│   └── smoke.sh                # Smoke test suite
└── specs/
    └── 001-schema-registry-image/  # Feature specification
```

## Making Changes

### Development Process

1. **Create Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make Changes**
   - Follow existing code style and conventions
   - Update documentation for user-facing changes
   - Add/update tests as needed

3. **Test Locally**
   ```bash
   # Build and test your changes
   make clean
   make build
   make test
   
   # Test with Chainguard base images
   make build RUNTIME_IMAGE=cgr.dev/chainguard/jre:latest
   make test
   
   # Optional: Test provenance generation locally
   # See docs/local-provenance-testing.md for details
   ```

4. **Verify Multi-Arch Builds**
   ```bash
   # Build for both architectures
   make buildx
   
   # Inspect manifest
   docker buildx imagetools inspect ib-schema-registry:latest
   ```

5. **Commit Changes**
   ```bash
   git add .
   git commit -m "feat: your feature description"
   ```

6. **Push and Create Pull Request**
   ```bash
   git push origin feature/your-feature-name
   # Open PR on GitHub
   ```

### Commit Message Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style (formatting, no logic change)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Build process, tooling, dependencies

**Examples**:
```
feat(dockerfile): add support for distroless base images
fix(makefile): correct platform detection on Apple Silicon
docs(readme): add troubleshooting section for build errors
test(smoke): add OCI label validation
```

## Testing Guidelines

### Running Tests

```bash
# Run smoke tests
make test

# Run smoke tests with custom image
./tests/smoke.sh my-image:my-tag

# Manual testing
docker run -d -p 8081:8081 ib-schema-registry:latest
curl http://localhost:8081/subjects
```

### Provenance Testing

**For Contributors**: Pull request builds automatically skip provenance generation. This is expected behavior and will not affect your PR.

**For Maintainers**: After merging to main or creating a release, verify provenance attestations:

```bash
# After merge to main
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:main

# After release tag
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:v1.0.0

# Quick check with docker buildx
docker buildx imagetools inspect \
  ghcr.io/infobloxopen/ib-schema-registry:main \
  --format '{{json .Provenance}}' | jq '.SLSA.predicateType'
```

📘 **Full documentation**:
- [Provenance Verification Guide](docs/provenance-verification.md)
- [CI Provenance Behavior](docs/ci-provenance-guide.md)
- [Troubleshooting](docs/troubleshooting-provenance.md)

### Writing Tests

When adding new features, update `tests/smoke.sh` to include:

1. **Functionality validation**: Does the feature work as expected?
2. **Error handling**: Does it fail gracefully?
3. **Regression prevention**: Will this test catch future breaks?

### Test Requirements

All PRs must:
- ✅ Pass existing smoke tests
- ✅ Build successfully on both AMD64 and ARM64
- ✅ Work with default Eclipse Temurin base images
- ✅ Work with Chainguard alternative base images
- ✅ Include tests for new functionality
- ✅ Not break existing functionality

**Note on Provenance**: Pull request builds automatically skip provenance generation (this is expected behavior). Provenance attestations are only generated when images are pushed to the registry (merges to main, tagged releases). See [docs/ci-provenance-guide.md](docs/ci-provenance-guide.md) for details.

## Code Review Process

### Before Submitting PR

- [ ] Code builds successfully (`make build`)
- [ ] Tests pass (`make test`)
- [ ] Multi-arch build works (`make buildx`)
- [ ] Documentation updated (if user-facing change)
- [ ] Commit messages follow convention
- [ ] No merge conflicts with main branch

### Pull Request Template

```markdown
## Description
Brief description of the change

## Motivation
Why is this change needed?

## Testing
- [ ] Tested locally on macOS ARM64
- [ ] Tested locally on Linux x86_64
- [ ] Tested with Eclipse Temurin base images
- [ ] Tested with Chainguard base images
- [ ] Smoke tests pass
- [ ] Multi-arch build works

## Related Issues
Fixes #123

## Checklist
- [ ] Documentation updated
- [ ] Tests added/updated
- [ ] Commit messages follow convention
- [ ] Constitution compliance verified
```

### Review Criteria

Reviewers will check for:

1. **Correctness**: Does the change work as intended?
2. **Constitution Compliance**: Does it violate any non-negotiable principles?
3. **Testing**: Are changes adequately tested?
4. **Documentation**: Is user-facing documentation updated?
5. **Code Quality**: Is code clean, readable, maintainable?
6. **Licensing**: Does it comply with upstream license restrictions?

## Constitution Compliance

All changes must comply with the [project constitution](.specify/memory/constitution.md):

### Non-Negotiable Requirements

- ✅ **Multi-arch portability**: Works identically on macOS ARM and Linux x86
- ✅ **Base image pluggability**: No hardcoded base image references
- ✅ **Distroless compatibility**: No shell assumptions in runtime
- ✅ **Supply-chain security**: Non-root user, OCI labels, documented pinning
- ✅ **Licensing compliance**: No upstream code copied (submodule only)
- ✅ **Repository ergonomics**: Makefile targets documented and tested
- ✅ **Testing validation**: CI builds both architectures, smoke tests pass

### Validation

Before submitting PR:

```bash
# Verify constitution compliance
make build  # macOS ARM
make buildx # Multi-arch
make test   # Smoke tests
make build RUNTIME_IMAGE=cgr.dev/chainguard/jre:latest  # Pluggability
```

## Upstream Updates

### Updating Schema Registry Version

```bash
# Update submodule to latest upstream release
make submodule-update

# Or manually to specific version
cd upstream/schema-registry
git fetch --tags
git checkout v7.7.0
cd ../..

# Rebuild and test
make build
make test

# Commit submodule reference
git add upstream/schema-registry
git commit -m "chore(upstream): update Schema Registry to v7.7.0"
```

### Handling Upstream Build Changes

If upstream changes Maven build process:

1. Test build with new upstream version
2. Update Dockerfile RUN command if needed
3. Update documentation
4. Add notes to CHANGELOG.md
5. Submit PR with breaking change warning

## Release Process

### Versioning

Images are versioned as:
```
<upstream-version>+infoblox.<build-number>
```

Example: `7.6.1+infoblox.1`

### Creating Release

1. **Update Submodule** (if new upstream version)
   ```bash
   make submodule-update
   ```

2. **Build and Test**
   ```bash
   make clean
   make buildx
   make test
   ```

3. **Tag Release**
   ```bash
   git tag -a v7.6.1+infoblox.1 -m "Release 7.6.1+infoblox.1"
   git push origin v7.6.1+infoblox.1
   ```

4. **CI Automatic Build**
   - GitHub Actions builds multi-arch image
   - Pushes to ghcr.io with version tag

## Common Development Tasks

### Testing SBOM Generation

```bash
# Install SBOM tools (Syft and Grype)
make sbom-install-tools

# Build image
make build TAG=test

# Generate SBOM for native architecture
make sbom SBOM_TAG=test

# Validate SBOM and scan for vulnerabilities
make sbom-validate SBOM_TAG=test

# Generate SBOMs for all architectures
make buildx TAG=test
make sbom-multi SBOM_TAG=test

# Manually scan with Grype
grype sbom:build/sbom/test-amd64.cyclonedx.json

# Clean up SBOM artifacts
make sbom-clean
```

### Testing Different Base Images

```bash
# Eclipse Temurin (default)
make build

# Chainguard JRE
make build RUNTIME_IMAGE=cgr.dev/chainguard/jre:latest

# Chainguard Maven + JRE
make build \
  BUILDER_IMAGE=cgr.dev/chainguard/maven:latest-dev \
  RUNTIME_IMAGE=cgr.dev/chainguard/jre:latest

# Custom base images
make build \
  BUILDER_IMAGE=custom/maven:tag \
  RUNTIME_IMAGE=custom/jre:tag
```

### Debugging Build Issues

```bash
# Enable verbose output
DOCKER_BUILDKIT=1 docker build --progress=plain .

# Build specific stage
docker build --target builder -t schema-registry-builder .

# Inspect builder stage
docker run -it schema-registry-builder bash

# Check Maven cache
docker buildx du --filter type=exec.cachemount
```

### Local CI Testing

```bash
# Simulate CI workflow
docker buildx create --name multiarch --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/infobloxopen/schema-registry:test \
  --push \
  .
```

## Getting Help

- **Questions**: Open [GitHub Discussion](https://github.com/infobloxopen/ib-schema-registry/discussions)
- **Bugs**: Open [GitHub Issue](https://github.com/infobloxopen/ib-schema-registry/issues)
- **Security**: Email security@infoblox.com (do not open public issue)
- **Upstream Issues**: [Confluent Schema Registry](https://github.com/confluentinc/schema-registry/issues)

## Code of Conduct

Be respectful, professional, and constructive. We welcome contributors of all experience levels.

## License

By contributing, you agree that your contributions will be licensed under the MIT License (for build tooling).

---

**Thank you for contributing!** 🎉
