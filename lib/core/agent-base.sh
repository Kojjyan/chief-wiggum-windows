#!/usr/bin/env bash
# =============================================================================
# agent-base.sh - Base library for agent development
#
# Provides shared functions to reduce boilerplate across agents:
#   - Metadata setup (agent_init_metadata)
#   - Callback context management (agent_setup_context)
#   - Common dependency sourcing (agent_source_*)
#   - Default lifecycle hook implementations
#
# Usage:
#   source "$WIGGUM_HOME/lib/core/agent-base.sh"
#   agent_init_metadata "my-agent" "Description of what it does"
#   agent_source_core
#   agent_source_ralph
# =============================================================================

# Prevent double-sourcing
[ -n "${_AGENT_BASE_LOADED:-}" ] && return 0
_AGENT_BASE_LOADED=1

# =============================================================================
# METADATA SETUP
# =============================================================================

# Initialize agent metadata
#
# Args:
#   type        - Agent type identifier (e.g., "task-worker")
#   description - Human-readable description
#
# Sets and exports: AGENT_TYPE, AGENT_DESCRIPTION
agent_init_metadata() {
    local type="$1"
    local description="$2"

    AGENT_TYPE="$type"
    AGENT_DESCRIPTION="$description"
    export AGENT_TYPE AGENT_DESCRIPTION
}

# =============================================================================
# CALLBACK CONTEXT SETUP
# =============================================================================

# Agent context variables (set by agent_setup_context)
_AGENT_WORKER_DIR=""
_AGENT_WORKSPACE=""
_AGENT_PROJECT_DIR=""
_AGENT_TASK_ID=""

# Setup standard callback context for ralph loop
#
# Args:
#   worker_dir  - Worker directory path
#   workspace   - Workspace directory path (where code lives)
#   project_dir - Project root directory (optional)
#   task_id     - Task identifier (optional)
agent_setup_context() {
    _AGENT_WORKER_DIR="${1:-}"
    _AGENT_WORKSPACE="${2:-}"
    _AGENT_PROJECT_DIR="${3:-}"
    _AGENT_TASK_ID="${4:-}"
}

# Get context values (for use in callbacks)
agent_get_worker_dir() { echo "$_AGENT_WORKER_DIR"; }
agent_get_workspace() { echo "$_AGENT_WORKSPACE"; }
agent_get_project_dir() { echo "$_AGENT_PROJECT_DIR"; }
agent_get_task_id() { echo "$_AGENT_TASK_ID"; }

# =============================================================================
# DEPENDENCY SOURCING
# =============================================================================

# Source core dependencies (logger, defaults)
agent_source_core() {
    source "$WIGGUM_HOME/lib/core/logger.sh"
    source "$WIGGUM_HOME/lib/core/defaults.sh"
}

# Source ralph loop (main execution pattern)
agent_source_ralph() {
    source "$WIGGUM_HOME/lib/claude/run-claude-ralph-loop.sh"
}

# Source git operations
agent_source_git() {
    source "$WIGGUM_HOME/lib/git/worktree-helpers.sh"
    source "$WIGGUM_HOME/lib/git/git-operations.sh"
}

# Source task parsing utilities
agent_source_tasks() {
    source "$WIGGUM_HOME/lib/tasks/task-parser.sh"
}

# Source metrics and audit logging
agent_source_metrics() {
    source "$WIGGUM_HOME/lib/metrics/audit-logger.sh"
    source "$WIGGUM_HOME/lib/metrics/metrics-export.sh"
}

# Source violation monitoring
agent_source_violations() {
    source "$WIGGUM_HOME/lib/worker/violation-monitor.sh"
}

# Source agent registry (for sub-agent spawning)
agent_source_registry() {
    source "$WIGGUM_HOME/lib/worker/agent-registry.sh"
}

# Source file locking utilities
agent_source_lock() {
    source "$WIGGUM_HOME/lib/core/file-lock.sh"
}

# Source resume capabilities
agent_source_resume() {
    source "$WIGGUM_HOME/lib/claude/run-claude-resume.sh"
}

# =============================================================================
# LIFECYCLE HOOKS (Default Implementations)
# =============================================================================

# Called before PID file creation during agent initialization
# Override in agent to perform early setup
#
# Args:
#   worker_dir  - Worker directory path
#   project_dir - Project root directory
#
# Returns: 0 to continue, non-zero to abort
agent_on_init() {
    local worker_dir="$1"
    local project_dir="$2"
    # Default: no-op
    return 0
}

# Called after init, before agent_run
# Override in agent to perform pre-run setup
#
# Args:
#   worker_dir  - Worker directory path
#   project_dir - Project root directory
#
# Returns: 0 to continue, non-zero to abort
agent_on_ready() {
    local worker_dir="$1"
    local project_dir="$2"
    # Default: no-op
    return 0
}

# Called on validation/prerequisite failure
# Override in agent to handle errors
#
# Args:
#   worker_dir - Worker directory path
#   exit_code  - The exit code that will be returned
#   error_type - Type of error: "prereq", "output", "runtime"
agent_on_error() {
    local worker_dir="$1"
    local exit_code="$2"
    local error_type="$3"
    # Default: no-op
    return 0
}

# Called on INT/TERM signal before cleanup
# Override in agent to handle graceful shutdown
#
# Args:
#   signal - Signal name: "INT" or "TERM"
agent_on_signal() {
    local signal="$1"
    # Default: no-op
    return 0
}

# =============================================================================
# AGENT CONFIGURATION
# =============================================================================

# Load agent-specific configuration from config/agents.json
#
# Args:
#   agent_type - The agent type to load config for
#
# Sets global variables based on config (with env var overrides):
#   AGENT_CONFIG_MAX_ITERATIONS
#   AGENT_CONFIG_MAX_TURNS
#   AGENT_CONFIG_TIMEOUT_SECONDS
#   AGENT_CONFIG_AUTO_COMMIT
load_agent_config() {
    local agent_type="$1"
    local config_file="$WIGGUM_HOME/config/agents.json"

    # Initialize with defaults
    AGENT_CONFIG_MAX_ITERATIONS=10
    AGENT_CONFIG_MAX_TURNS=30
    AGENT_CONFIG_TIMEOUT_SECONDS=3600
    AGENT_CONFIG_AUTO_COMMIT=false

    # Load from config file if it exists
    if [ -f "$config_file" ]; then
        # Load agent-specific config, falling back to defaults
        local agent_config default_config

        # Get defaults section
        default_config=$(jq -r '.defaults // {}' "$config_file" 2>/dev/null)
        if [ -n "$default_config" ] && [ "$default_config" != "null" ]; then
            AGENT_CONFIG_MAX_ITERATIONS=$(echo "$default_config" | jq -r '.max_iterations // 10')
            AGENT_CONFIG_MAX_TURNS=$(echo "$default_config" | jq -r '.max_turns // 30')
            AGENT_CONFIG_TIMEOUT_SECONDS=$(echo "$default_config" | jq -r '.timeout_seconds // 3600')
            AGENT_CONFIG_AUTO_COMMIT=$(echo "$default_config" | jq -r '.auto_commit // false')
        fi

        # Override with agent-specific config
        agent_config=$(jq -r ".agents.\"$agent_type\" // {}" "$config_file" 2>/dev/null)
        if [ -n "$agent_config" ] && [ "$agent_config" != "null" ] && [ "$agent_config" != "{}" ]; then
            local val

            val=$(echo "$agent_config" | jq -r '.max_iterations // empty')
            [ -n "$val" ] && AGENT_CONFIG_MAX_ITERATIONS="$val"

            val=$(echo "$agent_config" | jq -r '.max_turns // empty')
            [ -n "$val" ] && AGENT_CONFIG_MAX_TURNS="$val"

            val=$(echo "$agent_config" | jq -r '.timeout_seconds // empty')
            [ -n "$val" ] && AGENT_CONFIG_TIMEOUT_SECONDS="$val"

            val=$(echo "$agent_config" | jq -r '.auto_commit // empty')
            [ -n "$val" ] && AGENT_CONFIG_AUTO_COMMIT="$val"
        fi
    fi

    # Export for use by agent
    export AGENT_CONFIG_MAX_ITERATIONS
    export AGENT_CONFIG_MAX_TURNS
    export AGENT_CONFIG_TIMEOUT_SECONDS
    export AGENT_CONFIG_AUTO_COMMIT
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Create standard directory structure for an agent
#
# Args:
#   worker_dir - Worker directory path
agent_create_directories() {
    local worker_dir="$1"
    mkdir -p "$worker_dir/logs"
    mkdir -p "$worker_dir/summaries"
}

# Log agent start event
#
# Args:
#   worker_dir - Worker directory path
#   task_id    - Task identifier (optional)
agent_log_start() {
    local worker_dir="$1"
    local task_id="${2:-unknown}"
    local worker_id
    worker_id=$(basename "$worker_dir")

    echo "[$(date -Iseconds)] AGENT_STARTED agent=$AGENT_TYPE worker_id=$worker_id task_id=$task_id start_time=$(date +%s)" >> "$worker_dir/worker.log"
}

# Log agent completion event
#
# Args:
#   worker_dir - Worker directory path
#   exit_code  - Exit code from agent_run
#   start_time - Start timestamp (from date +%s)
agent_log_complete() {
    local worker_dir="$1"
    local exit_code="$2"
    local start_time="$3"

    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))

    echo "[$(date -Iseconds)] AGENT_COMPLETED agent=$AGENT_TYPE duration_sec=$duration exit_code=$exit_code" >> "$worker_dir/worker.log"
}
