#!/usr/bin/env bash
# platform.sh - Platform-specific compatibility helpers
#
# Provides portable implementations of commands that differ between
# GNU (Linux) and BSD (macOS) systems.
#
# Source this file when you need: find_newest, find_oldest, grep_pcre_match, etc.
set -euo pipefail

# Prevent double-sourcing
[ -n "${_PLATFORM_LOADED:-}" ] && return 0
_PLATFORM_LOADED=1

# =============================================================================
# PLATFORM DETECTION (cached at source time)
# =============================================================================

# Detect GNU find (supports -printf) vs BSD find (macOS)
if find . -maxdepth 0 -printf '' 2>/dev/null; then
    _FIND_HAS_PRINTF=1
else
    _FIND_HAS_PRINTF=0
fi

# =============================================================================
# PORTABLE SED
# =============================================================================

# Portable sed in-place edit (works on both GNU sed and BSD sed on macOS)
# Usage: sed_inplace <sed_expression> <file>
# Example: sed_inplace 's/foo/bar/' myfile.txt
sed_inplace() {
    if [[ "$OSTYPE" == darwin* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# =============================================================================
# PORTABLE FIND (mtime sorting)
# =============================================================================

# Portable find newest/oldest file by mtime (works on GNU and BSD find)
# Usage: find_newest <find_args...>
# Usage: find_oldest <find_args...>
# Example: find_newest "$dir" -name "*.log"
# Returns: Path to the newest/oldest file, or empty string if none found
#
# Note: On GNU find, uses -printf for efficiency. On BSD (macOS), falls back to ls -t.
find_newest() {
    if [ "$_FIND_HAS_PRINTF" = "1" ]; then
        # GNU find: use -printf for mtime sorting
        find "$@" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
    else
        # BSD find (macOS): use ls -t for mtime sorting
        # shellcheck disable=SC2012
        find "$@" -print0 2>/dev/null | xargs -0 ls -dt 2>/dev/null | head -1
    fi
}

find_oldest() {
    if [ "$_FIND_HAS_PRINTF" = "1" ]; then
        # GNU find: use -printf for mtime sorting
        find "$@" -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-
    else
        # BSD find (macOS): use ls -tr for mtime sorting (oldest first)
        # shellcheck disable=SC2012
        find "$@" -print0 2>/dev/null | xargs -0 ls -dtr 2>/dev/null | head -1
    fi
}

# List all matching files sorted by mtime (oldest first)
# Usage: find_sorted_by_mtime <find_args...>
# Returns: One file path per line, oldest first
find_sorted_by_mtime() {
    if [ "$_FIND_HAS_PRINTF" = "1" ]; then
        # GNU find: use -printf for mtime sorting
        find "$@" -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-
    else
        # BSD find (macOS): use ls -tr for mtime sorting
        # shellcheck disable=SC2012
        find "$@" -print0 2>/dev/null | xargs -0 ls -dtr 2>/dev/null
    fi
}

# =============================================================================
# PORTABLE DATE
# =============================================================================

# Parse a date string or epoch timestamp to epoch seconds
# Works on both GNU (Linux) and BSD (macOS) date commands
#
# Usage: date_parse_epoch <date_string_or_epoch>
# Examples:
#   date_parse_epoch "2024-01-26"           -> epoch
#   date_parse_epoch "2024-01-26T10:30:00"  -> epoch
#   date_parse_epoch "@1706270400"          -> 1706270400
#   date_parse_epoch "1706270400"           -> 1706270400 (if numeric)
#
# Returns: epoch timestamp on stdout, or empty on failure
date_parse_epoch() {
    local input="$1"

    # If already an epoch timestamp (numeric), return as-is
    if [[ "$input" =~ ^@?[0-9]+$ ]]; then
        echo "${input#@}"
        return 0
    fi

    # Try GNU date first (Linux)
    local epoch
    epoch=$(date -d "$input" +%s 2>/dev/null) && { echo "$epoch"; return 0; }

    # Try BSD date (macOS) - handles ISO 8601 format
    # Try common formats
    for fmt in "%Y-%m-%d" "%Y-%m-%dT%H:%M:%S" "%Y-%m-%d %H:%M:%S"; do
        epoch=$(date -j -f "$fmt" "$input" +%s 2>/dev/null) && { echo "$epoch"; return 0; }
    done

    # Failed to parse
    return 1
}

# Format an epoch timestamp to a date string
# Works on both GNU (Linux) and BSD (macOS) date commands
#
# Usage: date_format_epoch <epoch> <format>
# Examples:
#   date_format_epoch 1706270400 "%Y-%m-%d"       -> "2024-01-26"
#   date_format_epoch 1706270400 "%H:%M:%S"       -> "10:30:00"
#   date_format_epoch 1706270400 "%Y-%m-%dT%H:%M:%S" -> "2024-01-26T10:30:00"
#
# Returns: formatted date string on stdout
date_format_epoch() {
    local epoch="$1"
    local format="$2"

    # Try GNU date first (Linux)
    date -d "@$epoch" +"$format" 2>/dev/null && return 0

    # Try BSD date (macOS)
    date -r "$epoch" +"$format" 2>/dev/null && return 0

    # Failed
    return 1
}

# Get today's midnight as epoch timestamp
# Works on both GNU (Linux) and BSD (macOS)
#
# Usage: date_today_midnight
# Returns: epoch timestamp for midnight today
date_today_midnight() {
    local today
    today=$(date +%Y-%m-%d)

    # Try GNU date first
    date -d "$today" +%s 2>/dev/null && return 0

    # Try BSD date
    date -j -f "%Y-%m-%d" "$today" +%s 2>/dev/null && return 0

    # Fallback: calculate manually
    local now hour min sec
    now=$(date +%s)
    hour=$(date +%H)
    min=$(date +%M)
    sec=$(date +%S)
    # Remove leading zeros for arithmetic
    hour=$((10#$hour))
    min=$((10#$min))
    sec=$((10#$sec))
    echo $(( now - (hour * 3600) - (min * 60) - sec ))
}

# =============================================================================
# PORTABLE GREP (Perl regex)
# =============================================================================

# Portable grep with Perl regex (works on GNU grep and macOS via perl)
# Usage: grep_pcre_match <pattern> [file]
# Equivalent to: grep -oP <pattern> [file]
# Returns: matching portions only, one per line
grep_pcre_match() {
    local pattern="$1"
    local file="${2:-}"
    if [[ "$OSTYPE" == darwin* ]]; then
        # macOS: use perl since grep doesn't support -P
        if [ -n "$file" ]; then
            perl -ne 'while (m{'"$pattern"'}g) { print "$&\n"; }' "$file" 2>/dev/null
        else
            perl -ne 'while (m{'"$pattern"'}g) { print "$&\n"; }' 2>/dev/null
        fi
    else
        # Linux: use native grep -oP
        if [ -n "$file" ]; then
            grep -oP "$pattern" "$file" 2>/dev/null
        else
            grep -oP "$pattern" 2>/dev/null
        fi
    fi
}

# Portable grep -qP equivalent (quiet test for Perl regex match)
# Usage: grep_pcre_test <pattern> [file]
# Returns: 0 if match found, 1 otherwise
grep_pcre_test() {
    local pattern="$1"
    local file="${2:-}"
    if [[ "$OSTYPE" == darwin* ]]; then
        # macOS: use perl since grep doesn't support -P
        if [ -n "$file" ]; then
            perl -ne 'exit 0 if m{'"$pattern"'}' "$file" 2>/dev/null && return 0
        else
            perl -ne 'exit 0 if m{'"$pattern"'}' 2>/dev/null && return 0
        fi
        return 1
    else
        # Linux: use native grep -qP
        if [ -n "$file" ]; then
            grep -qP "$pattern" "$file" 2>/dev/null
        else
            grep -qP "$pattern" 2>/dev/null
        fi
    fi
}
