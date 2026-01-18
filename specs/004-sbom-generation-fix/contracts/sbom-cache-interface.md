# Contract: SBOM Cache Storage Interface

**Date**: 2026-01-17  
**Purpose**: Define the interface and behavior contract for SBOM storage and idempotency checking

## Storage Interface

### Function: `detect_existing_sbom()`

**Purpose**: Check if an SBOM with matching digest already exists in cache.

**Input Parameters**:
- `sbom_file`: Filesystem path to new SBOM (e.g., `build/sbom/7.6.1-amd64.cyclonedx.json`)

**Output**:
- Returns: `EXIT_CODE` 0 if existing SBOM found, 1 if not found
- Side effects: Reads `${sbom_file}.metadata.json` if it exists

**Contract**:
```bash
if detect_existing_sbom "$sbom_file"; then
    # Metadata exists, proceed to verification
else
    # New SBOM, proceed to generation
fi
```

**Error Handling**:
- If metadata file is malformed JSON → log error, return 1 (treat as new)
- If metadata file is missing but SBOM file exists → log warning, treat as new
- If permissions denied on metadata file → log error, exit 1 (fail safe)

---

### Function: `compute_sbom_hash()`

**Purpose**: Calculate SHA256 hash of SBOM file for equivalence checking.

**Input Parameters**:
- `sbom_file`: Path to SBOM file

**Output**:
- Returns: SHA256 hash in format `sha256:[64 hex chars]`
- To stdout: Hash value only (no prefix, no newline for eval)

**Contract**:
```bash
NEW_HASH=$(compute_sbom_hash "$sbom_file")
STORED_HASH=$(jq -r '.content_hash' "${sbom_file}.metadata.json")
if [ "$NEW_HASH" = "$STORED_HASH" ]; then
    OPERATION="VERIFIED_IDENTICAL"
else
    OPERATION="UPDATED"
fi
```

**Error Handling**:
- If file doesn't exist → return empty string, log error
- If sha256sum not available → return empty string, log error with fallback instructions

---

### Function: `verify_sbom_identical()`

**Purpose**: Check if newly generated SBOM matches existing version.

**Input Parameters**:
- `sbom_file`: Path to newly generated SBOM
- `metadata_file`: Path to metadata.json (optional, derived from sbom_file if not provided)

**Output**:
- Returns: EXIT_CODE 0 if identical, 1 if different or no prior version
- Side effects: None (read-only)

**Contract**:
```bash
if verify_sbom_identical "$sbom_file"; then
    echo "SBOM is identical to previous version"
    exit 0
else
    echo "SBOM differs from previous version or is new"
    exit 1
fi
```

**Error Handling**:
- If metadata.json doesn't exist → return 1 (new SBOM)
- If content_hash field missing → return 1 (corrupted metadata, treat as new)
- If hash computation fails → return 1 and log warning (proceed to safe state)

---

### Function: `write_sbom_metadata()`

**Purpose**: Persist SBOM metadata to disk with digest and hash information.

**Input Parameters**:
- `sbom_file`: Path to SBOM file
- `image_ref`: Full image reference (e.g., `ghcr.io/infobloxopen/ib-schema-registry:7.6.1`)
- `digest`: Image digest (e.g., `sha256:a9f36f...`)
- `platform`: Target platform (e.g., `linux/amd64`)
- `operation`: Operation type (`GENERATED`, `VERIFIED_IDENTICAL`, `UPDATED`)

**Output**:
- Returns: EXIT_CODE 0 on success, 1 on failure
- Side effects: Writes `${sbom_file}.metadata.json`

**Contract**:
```bash
write_sbom_metadata "$sbom_file" "$image_ref" "$digest" "$platform" "GENERATED"
```

**Generated Metadata Format**:
```json
{
  "image": "ghcr.io/infobloxopen/ib-schema-registry:7.6.1",
  "digest": "sha256:a9f36f222baa73fd5590d4648446f9632a2db54e3e0f601994986440f232b249",
  "platform": "linux/amd64",
  "format": "cyclonedx-json",
  "generated_at": "2026-01-17T10:30:45Z",
  "tool": "syft",
  "tool_version": "1.0.0",
  "content_hash": "sha256:computed_hash_of_sbom",
  "operation": "GENERATED",
  "file_size_bytes": 15234,
  "output_file": "build/sbom/7.6.1-amd64.cyclonedx.json"
}
```

**Error Handling**:
- If directory doesn't exist → create it (mkdir -p)
- If metadata write fails → log error, exit 1
- If JSON is malformed → exit 1 and log error

---

### Function: `should_overwrite_sbom()`

**Purpose**: Determine if existing SBOM should be replaced with new version.

**Input Parameters**:
- `sbom_file`: Path to new SBOM
- `operation_type`: Determined operation type

**Output**:
- Returns: EXIT_CODE 0 if should overwrite, 1 if should preserve existing

**Contract**:
```bash
if should_overwrite_sbom "$sbom_file" "$OPERATION"; then
    # Replace existing SBOM file
    mv "$temp_sbom" "$sbom_file"
else
    # Preserve existing SBOM, discard new
    rm "$temp_sbom"
fi
```

**Decision Logic**:
- If operation is `GENERATED` → overwrite (0)
- If operation is `UPDATED` → overwrite (0)
- If operation is `VERIFIED_IDENTICAL` → preserve (1)

**Error Handling**:
- Invalid operation type → return 1 (fail safe: preserve existing)

---

## Concurrency Safety Contract

### Atomic File Operations

**Requirement**: SBOM writes must be atomic to prevent corruption during concurrent access.

**Implementation**:
1. Write new SBOM to temporary file: `${sbom_file}.tmp.$$`
2. Verify file integrity (valid JSON, non-empty)
3. Atomic rename: `mv -f ${sbom_file}.tmp.$ ${sbom_file}` (atomic at OS level)
4. Write metadata after SBOM is safely written

**Timeout Behavior**:
- If metadata.json is being written by another process (detected by file lock or hash mismatch), wait up to 3 seconds
- Retry hash verification every 500ms
- If no consistency achieved within timeout, log warning and proceed (eventual consistency)

---

## Filesystem Contract

### Directory Structure

- **SBOM artifacts**: Stored in `build/sbom/` directory
- **Directory creation**: Must be created if doesn't exist (recursive mkdir)
- **File permissions**: Default umask (0644 for files, 0755 for directories)
- **Ownership**: Inherited from parent directory (no special ownership required)

### Naming Convention

Format: `[image-tag]-[arch].[format].json` and `[image-tag]-[arch].[format].metadata.json`

Examples:
- SBOM: `build/sbom/7.6.1-amd64.cyclonedx.json`
- Metadata: `build/sbom/7.6.1-amd64.cyclonedx.metadata.json`
- SBOM: `build/sbom/latest-arm64.spdx.json`
- Metadata: `build/sbom/latest-arm64.spdx.metadata.json`

### Cleanup Policy

- Old SBOM files (from prior builds) are **NOT automatically deleted**
- Manual cleanup via `make clean` or `rm -rf build/sbom/*`
- Archival/retention is user responsibility

---

## Status Reporting Contract

### Operation Status Codes

| Status | Meaning | Exit Code | User Visible |
|--------|---------|-----------|--------------|
| GENERATED | New SBOM created | 0 | ✓ |
| VERIFIED_IDENTICAL | Existing SBOM verified | 0 | ✓ |
| UPDATED | Existing SBOM replaced | 0 | ✓ |
| ERROR_GENERATION | Syft generation failed | 1 | ✓ |
| ERROR_HASH_MISMATCH | Hash verification failed | 1 | ✓ |
| ERROR_WRITE | File write failed | 1 | ✓ |

### Output Format

To stdout (user-facing):
```
✓ SBOM generated successfully
  File: build/sbom/7.6.1-amd64.cyclonedx.json
  Size: 15K
  Operation: GENERATED
  Digest: sha256:a9f36f222baa73fd5590d4648446f9632a2db54e3e0f601994986440f232b249
  Hash: sha256:b8c47e555caa84ge6691e5759557d3cf3e3fc65e5f611993988552330g343350
```

To metadata.json:
```json
{
  "operation": "GENERATED",
  "generated_at": "2026-01-17T10:30:45Z",
  "content_hash": "sha256:b8c47e555caa84ge6691e5759557d3cf3e3fc65e5f611993988552330g343350"
}
```

---

## Backward Compatibility

### Existing SBOM Files Without Metadata

**Contract**: If SBOM file exists but metadata.json doesn't:
1. Treat as "new" (no prior metadata to check against)
2. Generate fresh SBOM
3. Create new metadata.json with `operation: "GENERATED"`
4. **Do NOT overwrite** old SBOM (user may have purpose for it)

**Rationale**: Graceful migration - users can continue to use old SBOMs while feature is enabled

