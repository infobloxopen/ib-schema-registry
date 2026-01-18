# ib-schema-registry Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-01-15

## Active Technologies
- YAML (Helm templates), Bash/Shell scripting for e2e tests (003-helm-chart)
- N/A (Schema Registry is stateless; state stored in Kafka) (003-helm-chart)
- YAML (GitHub Actions workflows), Shell (bash scripting for version manipulation), Helm 3.8+ CLI (005-helm-chart-automation)
- GHCR OCI registry at `ghcr.io/infobloxopen/ib-schema-registry` (coexists with Docker images via different media types) (005-helm-chart-automation)
- Java 17 (inherited from upstream Confluent Schema Registry) (007-jmx-prometheus-metrics)
- N/A (metrics are ephemeral, exported via HTTP) (007-jmx-prometheus-metrics)

- Java 17 (upstream Schema Registry requirement; OpenJDK/Temurin compatible) + Maven 3.x (build tool), Docker BuildKit 0.11+ (multi-platform support), Git (submodule management), upstream confluentinc/schema-registry (source) (001-schema-registry-image)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Java 17 (upstream Schema Registry requirement; OpenJDK/Temurin compatible)

## Code Style

Java 17 (upstream Schema Registry requirement; OpenJDK/Temurin compatible): Follow standard conventions

## Recent Changes
- 007-jmx-prometheus-metrics: Added Java 17 (inherited from upstream Confluent Schema Registry)
- 005-helm-chart-automation: Added YAML (GitHub Actions workflows), Shell (bash scripting for version manipulation), Helm 3.8+ CLI
- 003-helm-chart: Added YAML (Helm templates), Bash/Shell scripting for e2e tests


<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
