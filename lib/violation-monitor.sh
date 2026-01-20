#!/usr/bin/env bash
# violation-monitor.sh - Background monitor for workspace boundary violations
#
# Runs in background, periodically checks for changes in the main project repo
# that would indicate workspace violations or user edits during worker execution.
#
# Extracted from ralph-loop.sh for reuse by agents.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logger.sh"

# Global variable for violation monitor PID (needed for cleanup from signal handler)
VIOLATION_MONITOR_PID=""

# Start real-time violation monitor
#
# Args:
#   project_dir     - The main project directory to monitor
#   worker_dir      - Worker directory for logging
#   monitor_interval - Check interval in seconds (default: 30)
#
# Returns: The PID of the background monitor process (also sets VIOLATION_MONITOR_PID)
start_violation_monitor() {
    local project_dir="$1"
    local worker_dir="$2"
    local monitor_interval="${3:-30}"

    (
        while true; do
            sleep "$monitor_interval"

            # Check git status in project root (excluding .ralph directory)
            cd "$project_dir" 2>/dev/null || continue
            local modified=$(git status --porcelain 2>/dev/null | grep -v "^.. .ralph/" | head -5)

            if [[ -n "$modified" ]]; then
                local timestamp=$(date -Iseconds)

                # Check if worker directory still exists (worker may have been killed)
                if [[ ! -d "$worker_dir" ]]; then
                    # Worker directory gone, exit the monitor
                    exit 0
                fi

                # Log the real-time detection (suppress errors if dir disappears mid-write)
                {
                    echo "[$timestamp] REAL-TIME VIOLATION DETECTED"
                    echo "Modified files in main repo:"
                    echo "$modified"
                    echo "---"
                } >> "$worker_dir/violation-monitor.log" 2>/dev/null || exit 0

                # Create flag file for worker to check (optional early termination)
                {
                    echo "VIOLATION_DETECTED"
                    echo "$timestamp"
                    echo "$modified"
                } > "$worker_dir/violation_flag.txt" 2>/dev/null || true

                # Log to stderr so it appears in worker output
                echo "[VIOLATION MONITOR] Changes detected in main repository!" >&2
                echo "[VIOLATION MONITOR] This will cause task failure at cleanup." >&2
                echo "[VIOLATION MONITOR] Files: $(echo "$modified" | head -1)" >&2
            fi
        done
    ) &

    VIOLATION_MONITOR_PID=$!
    log_debug "Violation monitor started with PID: $VIOLATION_MONITOR_PID"
    echo "$VIOLATION_MONITOR_PID"
}

# Stop the violation monitor
#
# Args:
#   monitor_pid - The PID of the monitor to stop (optional, uses VIOLATION_MONITOR_PID if not provided)
stop_violation_monitor() {
    local monitor_pid="${1:-$VIOLATION_MONITOR_PID}"

    if [[ -n "$monitor_pid" ]] && kill -0 "$monitor_pid" 2>/dev/null; then
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
        log_debug "Violation monitor stopped (PID: $monitor_pid)"
    fi

    # Clear global if we stopped it
    if [[ "$monitor_pid" == "$VIOLATION_MONITOR_PID" ]]; then
        VIOLATION_MONITOR_PID=""
    fi
}

# Check if a violation has been detected
#
# Args:
#   worker_dir - Worker directory to check
#
# Returns: 0 if violation detected, 1 otherwise
has_violation() {
    local worker_dir="$1"
    [[ -f "$worker_dir/violation_flag.txt" ]]
}
