# SBOM (Software Bill of Materials) Directory

This directory contains generated Software Bill of Materials (SBOM) files for the ib-schema-registry container images.

## What is an SBOM?

An SBOM is a comprehensive list of all components, libraries, and dependencies contained in a software artifact. SBOMs are essential for:

- **Security**: Identify and track vulnerabilities in dependencies
- **Compliance**: License compliance and supply chain transparency
- **Risk Management**: Understand the security posture of your container images

## Generated Files

SBOMs are generated in two industry-standard formats:

### CycloneDX Format

- **File Pattern**: `<tag>-<arch>.cyclonedx.json`
- **Spec Version**: 1.5
- **Use Case**: Recommended for vulnerability scanning and security analysis
- **Tools**: Compatible with Grype, Trivy, Dependency-Track

### SPDX Format

- **File Pattern**: `<tag>-<arch>.spdx.json`
- **Spec Version**: 2.3
- **Use Case**: License compliance and legal analysis
- **Tools**: Compatible with SPDX tools, FOSSology

### Metadata Files

- **File Pattern**: `<tag>-<arch>.<format>.metadata.json`
- **Content**: Generation timestamp, tool version, platform info

## Multi-Architecture Support

SBOMs are generated per platform to accurately reflect architecture-specific components:

- `latest-amd64.cyclonedx.json` - AMD64/x86_64 architecture
- `latest-arm64.cyclonedx.json` - ARM64/aarch64 architecture

Different architectures may have different base images and dependencies, so separate SBOMs ensure accuracy.

## Usage

### Generate SBOMs Locally

```bash
# Build image first
make build

# Generate SBOM for native architecture (both formats)
make sbom

# Generate SBOMs for all architectures
make sbom-multi

# Validate SBOMs and scan for vulnerabilities
make sbom-validate
```

### Scan for Vulnerabilities

Using Grype (Anchore):
```bash
grype sbom:build/sbom/latest-amd64.cyclonedx.json
```

Using Trivy (Aqua Security):
```bash
trivy sbom build/sbom/latest-amd64.cyclonedx.json
```

### View SBOM Content

Pretty-print with jq:
```bash
cat build/sbom/latest-amd64.cyclonedx.json | jq .
```

List all components:
```bash
# CycloneDX
cat build/sbom/latest-amd64.cyclonedx.json | jq '.components[].name'

# SPDX
cat build/sbom/latest-amd64.spdx.json | jq '.packages[].name'
```

## CI/CD Integration

SBOMs are automatically generated in GitHub Actions workflows:

1. **On every build**: SBOMs generated for both amd64 and arm64
2. **Stored as artifacts**: Available for download for 90 days
3. **Validation**: Automatically validated for correctness

### Download from GitHub Actions

```bash
# Using GitHub CLI
gh run download <run-id> -n sbom-cyclonedx-amd64
gh run download <run-id> -n sbom-spdx-amd64

# Using GitHub UI
# Navigate to Actions → Workflow Run → Artifacts section
```

## File Retention

- **Local builds**: Stored in `build/sbom/` until manually cleaned
- **CI/CD artifacts**: Retained for 90 days on GitHub
- **Cleanup**: Run `make sbom-clean` to remove local SBOMs

## SBOM Standards

### CycloneDX 1.5

- **Homepage**: https://cyclonedx.org/
- **Specification**: https://cyclonedx.org/docs/1.5/json/
- **Focus**: Security, vulnerability management, SBOM exchange

### SPDX 2.3

- **Homepage**: https://spdx.dev/
- **Specification**: https://spdx.github.io/spdx-spec/v2.3/
- **Focus**: License compliance, legal analysis, supply chain
- **Standard**: ISO/IEC 5962:2021

## Tools

### Generation

- **Syft** (Anchore Labs): Primary SBOM generation tool
  - Version: 1.0.0+
  - Homepage: https://github.com/anchore/syft
  - Install: `make sbom-install-tools`

### Validation & Scanning

- **Grype** (Anchore): Vulnerability scanner for containers and SBOMs
  - Homepage: https://github.com/anchore/grype
  - Install: `make sbom-install-tools`

- **Trivy** (Aqua Security): Comprehensive security scanner
  - Homepage: https://github.com/aquasecurity/trivy
  - Install: https://aquasecurity.github.io/trivy/latest/getting-started/installation/

## Troubleshooting

### "Syft is not installed"

```bash
make sbom-install-tools
```

### "Image not found"

Build the image before generating SBOMs:
```bash
make build TAG=test
make sbom SBOM_TAG=test
```

### Empty or Missing Components

- Ensure Docker image is built and available locally
- Check image architecture matches the requested platform
- Verify Syft version is 1.0.0 or newer

### Multi-Architecture SBOM Differences

This is expected! Different architectures use different base images:
- AMD64 typically uses larger, feature-rich base images
- ARM64 may use Chainguard or Alpine variants
- Component counts and dependencies will differ

## References

- **NTIA Minimum Elements**: https://www.ntia.gov/files/ntia/publications/sbom_minimum_elements_report.pdf
- **CISA SBOM Sharing**: https://www.cisa.gov/sbom
- **OpenSSF SBOM Everywhere**: https://openssf.org/community/sbom-everywhere/

## Support

For issues or questions:
- GitHub Issues: https://github.com/infobloxopen/ib-schema-registry/issues
- Documentation: See project README.md
