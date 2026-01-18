# Research: SBOM Generation Fix

**Date**: 2026-01-17  
**Purpose**: Resolve design unknowns and validate technical approach for idempotent SBOM generation

## Research Findings

### 1. Syft SBOM Generation Tool Behavior

**Investigation**: How does Syft behave when generating SBOM for the same image digest multiple times?

**Finding**: 
- Syft is deterministic: Same image digest produces bit-identical SBOM output when run multiple times (assuming same Syft version, no dependency updates in image)
- Syft does NOT fail or error when overwriting files - it simply replaces them
- The "cannot overwrite digest" error in GitHub issue #14 is **NOT from Syft itself**, but likely from a wrapping script or CI workflow that prevents file overwrites

**Rationale for Design**: 
- We can use SHA256 hash comparison of SBOM content (or metadata timestamp) to detect whether a regenerated SBOM is identical to existing one
- Instead of preventing overwrites, we verify equivalence and report success (not error) when identical

**Decision**: Implement hash-based verification in shell script (lightweight, no new dependencies)

---

### 2. File Path Strategy for SBOM Storage

**Investigation**: How should SBOMs be indexed and stored to support multi-arch builds without digest conflicts?

**Finding**:
- OCI image digests are per-architecture in multi-arch builds (distinct SHA256 for linux/amd64 vs linux/arm64)
- Current Makefile uses `build/sbom/[tag]-[arch].json` naming pattern (good: prevents cross-architecture conflicts)
- Hostname/registry not included in filenames (OK: registry-specific images should have unique tags locally)

**Rationale for Design**:
- Use image digest (SHA256) as primary index in metadata.json file
- Keep filesystem naming `[tag]-[arch].[format].json` (human-readable, consistent with current convention)
- Store digest in metadata for validation lookup

**Decision**: Maintain current filesystem structure, add digest tracking in metadata.json

---

### 3. Hash Comparison Mechanism

**Investigation**: What algorithm ensures SBOM equivalence without binary comparison overhead?

**Finding**:
- SHA256 hash of SBOM JSON file is reliable for equivalence checking
- CycloneDX and SPDX formats are stable: same input produces identical JSON (no timestamp drift in Syft)
- `sha256sum` is standard on Linux/macOS; jq can extract/normalize JSON if needed

**Rationale for Design**:
- File-level SHA256 hash sufficient for idempotency check
- Store hash in metadata.json during first generation
- On regeneration, compute new hash and compare against stored hash

**Decision**: Use SHA256 hash of SBOM file as idempotency verification

---

### 4. Concurrent Invocation Handling

**Investigation**: What happens if SBOM generation is triggered twice simultaneously for the same digest?

**Finding**:
- Shell script has no built-in file locking
- Filesystem operations (write) are atomic at OS level for small files
- Risk: Hash comparison reads old metadata while write is in progress

**Rationale for Design**:
- Add retry logic for hash verification (read → wait 1s → retry if mismatch)
- Create atomic operations using temp file + rename pattern
- Document as "best-effort" concurrent access (acceptable for build tools)

**Decision**: Use temp file + atomic rename; add 3-second timeout with retry for concurrent detection

---

### 5. Integration with Existing Generate-SBOM Script

**Investigation**: Should we modify existing `generate-sbom.sh` or create new wrapper script?

**Finding**:
- Current script is single-purpose: calls Syft, validates output
- Idempotent behavior is a wrapper concern (hash checking, caching logic)
- Minimal changes to existing script reduce regression risk

**Rationale for Design**:
- Create `scripts/sbom/lib-idempotent.sh` as sourced utility functions
- Enhance `generate-sbom.sh` to source utility library and call hash verification before output
- Maintains backward compatibility: script still generates SBOM same way, just adds verification step

**Decision**: Add library functions in new file; source from generate-sbom.sh

---

### 6. Logging and User Communication

**Investigation**: How should we communicate to users whether SBOM was new, verified identical, or updated?

**Finding**:
- Current script logs to stdout/stderr
- Users need clear signal that operation succeeded even if file wasn't "newly" generated
- CI/CD logs need audit trail (timestamp, hash, decision)

**Rationale for Design**:
- Add operation status output: "GENERATED", "VERIFIED_IDENTICAL", "UPDATED"
- Include hash in logged metadata for audit trail
- Use color codes (optional, disabled in CI) for visual clarity

**Decision**: Add exit messages and status flags in metadata.json

---

### 7. Testing Strategy

**Investigation**: How can we validate idempotent SBOM generation without complex test harness?

**Finding**:
- Smoke test: Build image, generate SBOM twice, verify both succeed
- Integration test: Run CI workflow, check for no errors on rebuild
- Unit test: shell test framework (bats) available but overkill for simple script

**Rationale for Design**:
- Makefile smoke test target: `make sbom-idempotent-test`
  - Builds image, generates SBOM, regenerates SBOM, checks hashes match
- CI/CD validation: Run sbom targets on push + rebuild from same source
- No new test infrastructure needed

**Decision**: Smoke tests via Makefile; CI/CD validates via existing workflow triggers

---

## Unresolved Questions

None remaining. All technical design decisions documented above.

## Summary of Design Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Hash Algorithm | SHA256 of SBOM file | Standard, reliable, fast comparison |
| Storage Structure | Keep current `[tag]-[arch].json` naming | Consistent with existing convention, prevents conflicts |
| Index Mechanism | Digest metadata in .metadata.json | Decouples human-readable filenames from unique digest tracking |
| Concurrency Handling | Temp file + rename + retry | Atomic at OS level; simple; acceptable for build tools |
| Implementation Approach | Enhance generate-sbom.sh via lib utility | Minimal changes, backward compatible, single responsibility |
| Status Communication | New operation status field in metadata | Clear audit trail, facilitates CI/CD parsing |
| Testing | Makefile smoke tests + CI validation | Lightweight, no new test infrastructure |

