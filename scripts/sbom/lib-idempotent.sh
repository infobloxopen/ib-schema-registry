#!/usr/bin/env bash
# =============================================================================
# SBOM Idempotent Caching Library
# =============================================================================
# Utility functions for idempotent SBOM generation with digest-based caching
#
# This library provides the core functions for:
# - Detecting existing SBOMs by digest
# - Computing and comparing hashes for content equivalence
# - Managing SBOM metadata for audit trail
# - Handling concurrent access safely
#
# Sourced by: scripts/sbom/generate-sbom.sh
# Contract: scripts/sbom/contracts/sbom-cache-interface.md
# =============================================================================

set -euo pipefail

# =============================================================================
# Function: detect_existing_sbom()
# Purpose: Check if SBOM metadata exists for given file
# Returns: 0 if exists, 1 if not found
# =============================================================================
detect_existing_sbom() {
    local sbom_file="$1"
    local metadata_file="${sbom_file}.metadata.json"
    
    if [ ! -f "$metadata_file" ]; then
        return 1
    fi
    
    # Verify metadata is valid JSON
    if ! jq empty "$metadata_file" 2>/dev/null; then
        echo "Warning: Metadata file is malformed JSON: $metadata_file" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# Function: compute_sbom_hash()
# Purpose: Calculate SHA256 hash of SBOM file for equivalence verification
# Returns: SHA256 hash in format sha256:XXXXXX..., empty if file not found
# =============================================================================
compute_sbom_hash() {
    local sbom_file="$1"
    
    if [ ! -f "$sbom_file" ]; then
        echo "" >&2
        return 1
    fi
    
    # Use native sha256sum on Linux, shasum on macOS
    if command -v sha256sum &> /dev/null; then
        sha256sum "$sbom_file" | awk '{print "sha256:" $1}'
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$sbom_file" | awk '{print "sha256:" $1}'
    else
        echo "Error: Neither sha256sum nor shasum found" >&2
        return 1
    fi
}

# =============================================================================
# Function: verify_sbom_identical()
# Purpose: Check if SBOM exists for the same image digest (idempotency check)
# Args: $1 = SBOM file path, $2 = current image digest
# Returns: 0 if same digest exists, 1 if different digest or no prior version
# Note: Uses digest comparison, not content hash, because SBOM timestamps vary
# =============================================================================
verify_sbom_identical() {
    local sbom_file="$1"
    local current_digest="$2"
    local metadata_file="${sbom_file}.metadata.json"
    
    # If metadata doesn't exist, this is a new SBOM
    if [ ! -f "$metadata_file" ]; then
        return 1
    fi
    
    # Extract stored digest from metadata
    local stored_digest
    stored_digest=$(jq -r '.digest // empty' "$metadata_file" 2>/dev/null) || return 1
    
    if [ -z "$stored_digest" ]; then
        echo "Warning: digest field missing from metadata" >&2
        return 1
    fi
    
    # Compare digests (idempotency based on image digest, not SBOM content)
    if [ "$current_digest" = "$stored_digest" ]; then
        return 0  # Same digest = idempotent
    fi
    
    return 1  # Different digest = needs update
}

# =============================================================================
# Function: write_sbom_metadata()
# Purpose: Persist SBOM metadata to disk
# Arguments:
#   sbom_file: Path to SBOM file
#   image_ref: Full image reference (e.g., ghcr.io/org/image:tag)
#   digest: Image digest (sha256:XXXX)
#   platform: Target platform (linux/amd64 or linux/arm64)
#   operation: Operation type (GENERATED, VERIFIED_IDENTICAL, UPDATED)
# Returns: 0 on success, 1 on failure
# =============================================================================
write_sbom_metadata() {
    local sbom_file="$1"
    local image_ref="$2"
    local digest="$3"
    local platform="$4"
    local operation="$5"
    
    local metadata_file="${sbom_file}.metadata.json"
    local metadata_dir
    metadata_dir=$(dirname "$metadata_file")
    
    # Create directory if needed
    mkdir -p "$metadata_dir"
    
    # Compute file size and content hash
    local file_size
    local content_hash
    
    if [ ! -f "$sbom_file" ]; then
        echo "Error: SBOM file not found: $sbom_file" >&2
        return 1
    fi
    
    file_size=$(stat -f%z "$sbom_file" 2>/dev/null || stat -c%s "$sbom_file" 2>/dev/null || echo 0)
    content_hash=$(compute_sbom_hash "$sbom_file") || return 1
    
    # Determine format from file extension
    local format
    if [[ "$sbom_file" == *"cyclonedx"* ]]; then
        format="cyclonedx-json"
    elif [[ "$sbom_file" == *"spdx"* ]]; then
        format="spdx-json"
    else
        format="unknown"
    fi
    
    # Get Syft version
    local tool_version
    tool_version=$(syft version 2>&1 | grep -i version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "unknown")
    
    # Create metadata JSON using heredoc
    cat > "$metadata_file" <<EOF
{
  "image": "$image_ref",
  "digest": "$digest",
  "platform": "$platform",
  "format": "$format",
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "tool": "syft",
  "tool_version": "$tool_version",
  "content_hash": "$content_hash",
  "operation": "$operation",
  "file_size_bytes": $file_size,
  "output_file": "$sbom_file"
}
EOF
    
    if [ ! -f "$metadata_file" ]; then
        echo "Error: Failed to write metadata file: $metadata_file" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# Function: should_overwrite_sbom()
# Purpose: Determine if SBOM file should be overwritten based on operation
# Arguments:
#   operation: GENERATED, VERIFIED_IDENTICAL, UPDATED
# Returns: 0 if should overwrite, 1 if should preserve
# =============================================================================
should_overwrite_sbom() {
    local operation="$1"
    
    case "$operation" in
        GENERATED|UPDATED)
            return 0  # Yes, overwrite
            ;;
        VERIFIED_IDENTICAL)
            return 1  # No, preserve existing
            ;;
        *)
            echo "Error: Invalid operation type: $operation" >&2
            return 1  # Fail safe: preserve existing
            ;;
    esac
}

# =============================================================================
# Function: log_operation_status()
# Purpose: Log human-readable SBOM operation status
# Arguments:
#   status: GENERATED, VERIFIED_IDENTICAL, or UPDATED
#   sbom_file: Path to SBOM file
#   file_size: Size of SBOM in bytes (optional)
# =============================================================================
log_operation_status() {
    local status="$1"
    local sbom_file="$2"
    local file_size="${3:-}"
    
    case "$status" in
        GENERATED)
            echo "✓ SBOM generated successfully"
            ;;
        VERIFIED_IDENTICAL)
            echo "✓ SBOM verified identical (no changes)"
            ;;
        UPDATED)
            echo "✓ SBOM updated (image changed)"
            ;;
        *)
            echo "⚠ SBOM operation: $status"
            ;;
    esac
    
    if [ -f "$sbom_file" ]; then
        local size
        size=$(ls -lh "$sbom_file" | awk '{print $5}')
        echo "  File: $sbom_file"
        echo "  Size: $size"
        echo "  Operation: $status"
    fi
}

# =============================================================================
# Function: atomic_sbom_rename()
# Purpose: Atomically move SBOM file from temp location, handle concurrent access
# Arguments:
#   temp_file: Temporary file location
#   target_file: Final SBOM location
# Returns: 0 on success, 1 on failure
# =============================================================================
atomic_sbom_rename() {
    local temp_file="$1"
    local target_file="$2"
    local max_retries=3
    local retry_delay=1
    
    if [ ! -f "$temp_file" ]; then
        echo "Error: Temp file not found: $temp_file" >&2
        return 1
    fi
    
    # Try atomic rename with retry logic for concurrent access
    local attempt=0
    while [ $attempt -lt $max_retries ]; do
        if mv -f "$temp_file" "$target_file" 2>/dev/null; then
            return 0
        fi
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_retries ]; then
            sleep $retry_delay
        fi
    done
    
    echo "Error: Failed to move SBOM file after $max_retries attempts" >&2
    return 1
}

# =============================================================================
# Function: validate_sbom_format()
# Purpose: Validate SBOM file is valid JSON and not empty
# Arguments:
#   sbom_file: Path to SBOM file
# Returns: 0 if valid, 1 if invalid
# =============================================================================
validate_sbom_format() {
    local sbom_file="$1"
    
    if [ ! -f "$sbom_file" ]; then
        echo "Error: SBOM file not found: $sbom_file" >&2
        return 1
    fi
    
    # Check file is not empty
    if [ ! -s "$sbom_file" ]; then
        echo "Error: SBOM file is empty: $sbom_file" >&2
        return 1
    fi
    
    # Validate JSON syntax
    if ! jq empty "$sbom_file" 2>/dev/null; then
        echo "Error: SBOM file is not valid JSON: $sbom_file" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# Export functions for use in sourcing scripts
# =============================================================================
export -f detect_existing_sbom
export -f compute_sbom_hash
export -f verify_sbom_identical
export -f write_sbom_metadata
export -f should_overwrite_sbom
export -f log_operation_status
export -f atomic_sbom_rename
export -f validate_sbom_format
