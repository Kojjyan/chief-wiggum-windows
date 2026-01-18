#!/usr/bin/env bash
# Logging utilities for Chief Wiggum

log() {
    local message="$1"
    echo "[$(date -Iseconds)] $message"
}

log_error() {
    local message="$1"
    echo "[$(date -Iseconds)] ERROR: $message" >&2
}

log_debug() {
    local message="$1"
    if [ "${DEBUG:-0}" = "1" ]; then
        echo "[$(date -Iseconds)] DEBUG: $message" >&2
    fi
}
