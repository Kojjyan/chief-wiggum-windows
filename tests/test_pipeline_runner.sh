#!/usr/bin/env bash
# =============================================================================
# Tests for lib/pipeline/pipeline-runner.sh
#
# Tests pipeline execution including:
# - Step sequencing (runs in order)
# - enabled_by condition checking
# - depends_on condition checking
# - Blocking vs non-blocking failure handling
# - Fix retry loop
# - Step config writing
# - start_from_step resolution
# =============================================================================

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIGGUM_HOME="$(dirname "$TESTS_DIR")"
export WIGGUM_HOME

source "$TESTS_DIR/test-framework.sh"

TEST_DIR=""

# Stub functions that pipeline-runner.sh expects from system.task-worker context
_phase_start() { :; }
_phase_end() { :; }
_commit_subagent_changes() { :; }
export -f _phase_start _phase_end _commit_subagent_changes

setup() {
    TEST_DIR=$(mktemp -d)
    export LOG_FILE="$TEST_DIR/test.log"
    export WIGGUM_TASK_ID="TEST-001"

    # Create project and worker dirs
    mkdir -p "$TEST_DIR/project/.ralph/logs"
    mkdir -p "$TEST_DIR/worker/workspace" "$TEST_DIR/worker/logs" "$TEST_DIR/worker/results"

    # Reset loaded state to allow fresh sourcing
    unset _PIPELINE_LOADER_LOADED _PIPELINE_RUNNER_LOADED _ACTIVITY_LOG_LOADED 2>/dev/null || true

    source "$WIGGUM_HOME/lib/core/logger.sh"
    source "$WIGGUM_HOME/lib/utils/activity-log.sh"
    activity_init "$TEST_DIR/project"
    source "$WIGGUM_HOME/lib/pipeline/pipeline-loader.sh"
}

teardown() {
    unset WIGGUM_TASK_ID WIGGUM_STEP_ID WIGGUM_STEP_READONLY
    rm -rf "$TEST_DIR"
}

# Helper: Create a pipeline JSON file
_create_pipeline() {
    local file="$1"
    local json="$2"
    echo "$json" > "$file"
    pipeline_load "$file" 2>/dev/null
}

# Helper: Create a mock agent that records invocations
_create_mock_agent() {
    local agent_name="$1"
    local result="${2:-PASS}"  # PASS, FAIL, FIX, STOP

    local agent_dir="$TEST_DIR/fake-home/lib/agents"
    mkdir -p "$agent_dir"

    cat > "$agent_dir/${agent_name}.sh" << EOF
agent_required_paths() { echo ""; }
agent_run() {
    local worker_dir="\$1"
    echo "${agent_name}" >> "$TEST_DIR/agent_invocations.txt"
    # Write result file
    local step_id="\${WIGGUM_STEP_ID:-unknown}"
    mkdir -p "\$worker_dir/results"
    echo '{"gate_result": "${result}"}' > "\$worker_dir/results/\${step_id}.json"
}
EOF
}

# Stub: agent_read_step_result reads from results/
agent_read_step_result() {
    local worker_dir="$1"
    local step_id="$2"
    local result_file="$worker_dir/results/${step_id}.json"
    if [ -f "$result_file" ]; then
        jq -r '.gate_result // "UNKNOWN"' "$result_file" 2>/dev/null
    else
        echo "UNKNOWN"
    fi
}

# Stub: run_sub_agent calls agent_run from the mocked agent
run_sub_agent() {
    local agent_type="$1"
    local worker_dir="$2"
    local project_dir="$3"

    local agent_file="$TEST_DIR/fake-home/lib/agents/${agent_type}.sh"
    if [ -f "$agent_file" ]; then
        # shellcheck source=/dev/null
        source "$agent_file"
        agent_run "$worker_dir" "$project_dir"
    else
        echo "mock-agent:$agent_type" >> "$TEST_DIR/agent_invocations.txt"
        # Write a PASS result by default
        local step_id="${WIGGUM_STEP_ID:-unknown}"
        mkdir -p "$worker_dir/results"
        echo '{"gate_result": "PASS"}' > "$worker_dir/results/${step_id}.json"
    fi
}

# =============================================================================
# Test: Pipeline runs steps in sequence
# =============================================================================
test_pipeline_runs_steps_in_order() {
    _create_pipeline "$TEST_DIR/pipeline.json" '{
        "name": "test-order",
        "steps": [
            {"id": "step-1", "agent": "agent-a"},
            {"id": "step-2", "agent": "agent-b"},
            {"id": "step-3", "agent": "agent-c"}
        ]
    }'

    # Reset pipeline-runner loaded flag and source
    unset _PIPELINE_RUNNER_LOADED 2>/dev/null || true
    source "$WIGGUM_HOME/lib/pipeline/pipeline-runner.sh"

    : > "$TEST_DIR/agent_invocations.txt"

    pipeline_run_all "$TEST_DIR/worker" "$TEST_DIR/project" "$TEST_DIR/worker/workspace" ""

    local invocations
    invocations=$(cat "$TEST_DIR/agent_invocations.txt")
    assert_output_contains "$invocations" "mock-agent:agent-a" "Step 1 agent should run"
    assert_output_contains "$invocations" "mock-agent:agent-b" "Step 2 agent should run"
    assert_output_contains "$invocations" "mock-agent:agent-c" "Step 3 agent should run"

    # Verify order (a before b before c)
    local line_a line_b line_c
    line_a=$(grep -n "agent-a" "$TEST_DIR/agent_invocations.txt" | head -1 | cut -d: -f1)
    line_b=$(grep -n "agent-b" "$TEST_DIR/agent_invocations.txt" | head -1 | cut -d: -f1)
    line_c=$(grep -n "agent-c" "$TEST_DIR/agent_invocations.txt" | head -1 | cut -d: -f1)

    ASSERTION_COUNT=$((ASSERTION_COUNT + 1))
    if [ "$line_a" -lt "$line_b" ] && [ "$line_b" -lt "$line_c" ]; then
        echo -e "  ${GREEN}✓${NC} Steps ran in correct order (a=$line_a, b=$line_b, c=$line_c)"
    else
        echo -e "  ${RED}✗${NC} Steps ran out of order (a=$line_a, b=$line_b, c=$line_c)"
        FAILED_ASSERTIONS=$((FAILED_ASSERTIONS + 1))
    fi
}

# =============================================================================
# Test: enabled_by skips steps when env var is not 'true'
# =============================================================================
test_pipeline_enabled_by_skips() {
    _create_pipeline "$TEST_DIR/pipeline.json" '{
        "name": "test-enabled-by",
        "steps": [
            {"id": "always", "agent": "agent-always"},
            {"id": "gated", "agent": "agent-gated", "enabled_by": "ENABLE_GATED_STEP"},
            {"id": "final", "agent": "agent-final"}
        ]
    }'

    unset _PIPELINE_RUNNER_LOADED 2>/dev/null || true
    source "$WIGGUM_HOME/lib/pipeline/pipeline-runner.sh"

    # Don't set ENABLE_GATED_STEP
    unset ENABLE_GATED_STEP 2>/dev/null || true
    : > "$TEST_DIR/agent_invocations.txt"

    pipeline_run_all "$TEST_DIR/worker" "$TEST_DIR/project" "$TEST_DIR/worker/workspace" ""

    local invocations
    invocations=$(cat "$TEST_DIR/agent_invocations.txt")
    assert_output_contains "$invocations" "agent-always" "Always step should run"
    assert_output_not_contains "$invocations" "agent-gated" "Gated step should be skipped"
    assert_output_contains "$invocations" "agent-final" "Final step should run"
}

# =============================================================================
# Test: enabled_by runs steps when env var is 'true'
# =============================================================================
test_pipeline_enabled_by_runs() {
    _create_pipeline "$TEST_DIR/pipeline.json" '{
        "name": "test-enabled-by-true",
        "steps": [
            {"id": "gated", "agent": "agent-gated", "enabled_by": "ENABLE_GATED_STEP"}
        ]
    }'

    unset _PIPELINE_RUNNER_LOADED 2>/dev/null || true
    source "$WIGGUM_HOME/lib/pipeline/pipeline-runner.sh"

    export ENABLE_GATED_STEP="true"
    : > "$TEST_DIR/agent_invocations.txt"

    pipeline_run_all "$TEST_DIR/worker" "$TEST_DIR/project" "$TEST_DIR/worker/workspace" ""

    local invocations
    invocations=$(cat "$TEST_DIR/agent_invocations.txt")
    assert_output_contains "$invocations" "agent-gated" "Gated step should run when enabled"
    unset ENABLE_GATED_STEP
}

# =============================================================================
# Test: depends_on skips step when dependency failed
# =============================================================================
test_pipeline_depends_on_skips_on_fail() {
    # Create a mock agent that writes FAIL result
    _create_mock_agent "dep-fail-agent" "FAIL"

    _create_pipeline "$TEST_DIR/pipeline.json" '{
        "name": "test-depends-on",
        "steps": [
            {"id": "dep-step", "agent": "dep-fail-agent", "blocking": false},
            {"id": "dependent", "agent": "agent-dependent", "depends_on": "dep-step"}
        ]
    }'

    unset _PIPELINE_RUNNER_LOADED 2>/dev/null || true
    source "$WIGGUM_HOME/lib/pipeline/pipeline-runner.sh"

    : > "$TEST_DIR/agent_invocations.txt"
    pipeline_run_all "$TEST_DIR/worker" "$TEST_DIR/project" "$TEST_DIR/worker/workspace" ""

    local invocations
    invocations=$(cat "$TEST_DIR/agent_invocations.txt")
    assert_output_not_contains "$invocations" "agent-dependent" \
        "Dependent step should be skipped when dependency failed"
}

# =============================================================================
# Test: Blocking step failure halts pipeline
# =============================================================================
test_pipeline_blocking_failure_halts() {
    _create_mock_agent "fail-agent" "FAIL"

    _create_pipeline "$TEST_DIR/pipeline.json" '{
        "name": "test-blocking",
        "steps": [
            {"id": "blocker", "agent": "fail-agent", "blocking": true},
            {"id": "after", "agent": "agent-after"}
        ]
    }'

    unset _PIPELINE_RUNNER_LOADED 2>/dev/null || true
    source "$WIGGUM_HOME/lib/pipeline/pipeline-runner.sh"

    : > "$TEST_DIR/agent_invocations.txt"
    local exit_code=0
    pipeline_run_all "$TEST_DIR/worker" "$TEST_DIR/project" "$TEST_DIR/worker/workspace" "" || exit_code=$?

    assert_equals "1" "$exit_code" "Pipeline should return 1 on blocking failure"

    local invocations
    invocations=$(cat "$TEST_DIR/agent_invocations.txt")
    assert_output_not_contains "$invocations" "agent-after" \
        "Steps after blocking failure should not run"
}

# =============================================================================
# Test: Non-blocking step failure continues pipeline
# =============================================================================
test_pipeline_nonblocking_failure_continues() {
    _create_mock_agent "soft-fail" "FAIL"

    _create_pipeline "$TEST_DIR/pipeline.json" '{
        "name": "test-nonblocking",
        "steps": [
            {"id": "soft", "agent": "soft-fail", "blocking": "false"},
            {"id": "continues", "agent": "agent-continues"}
        ]
    }'

    unset _PIPELINE_RUNNER_LOADED 2>/dev/null || true
    source "$WIGGUM_HOME/lib/pipeline/pipeline-runner.sh"

    : > "$TEST_DIR/agent_invocations.txt"
    local exit_code=0
    pipeline_run_all "$TEST_DIR/worker" "$TEST_DIR/project" "$TEST_DIR/worker/workspace" "" || exit_code=$?

    assert_equals "0" "$exit_code" "Pipeline should return 0 with non-blocking failure"

    local invocations
    invocations=$(cat "$TEST_DIR/agent_invocations.txt")
    assert_output_contains "$invocations" "agent-continues" \
        "Steps after non-blocking failure should continue"
}

# =============================================================================
# Test: start_from_step skips earlier steps
# =============================================================================
test_pipeline_start_from_step() {
    _create_pipeline "$TEST_DIR/pipeline.json" '{
        "name": "test-start-from",
        "steps": [
            {"id": "step-1", "agent": "agent-1"},
            {"id": "step-2", "agent": "agent-2"},
            {"id": "step-3", "agent": "agent-3"}
        ]
    }'

    unset _PIPELINE_RUNNER_LOADED 2>/dev/null || true
    source "$WIGGUM_HOME/lib/pipeline/pipeline-runner.sh"

    : > "$TEST_DIR/agent_invocations.txt"
    pipeline_run_all "$TEST_DIR/worker" "$TEST_DIR/project" "$TEST_DIR/worker/workspace" "step-2"

    local invocations
    invocations=$(cat "$TEST_DIR/agent_invocations.txt")
    assert_output_not_contains "$invocations" "agent-1" "Step 1 should be skipped"
    assert_output_contains "$invocations" "agent-2" "Step 2 should run"
    assert_output_contains "$invocations" "agent-3" "Step 3 should run"
}

# =============================================================================
# Test: Step config is written to worker dir
# =============================================================================
test_pipeline_writes_step_config() {
    _create_pipeline "$TEST_DIR/pipeline.json" '{
        "name": "test-config",
        "steps": [
            {"id": "configured", "agent": "agent-x", "config": {"max_turns": 10, "custom_key": "val"}}
        ]
    }'

    unset _PIPELINE_RUNNER_LOADED 2>/dev/null || true
    source "$WIGGUM_HOME/lib/pipeline/pipeline-runner.sh"

    : > "$TEST_DIR/agent_invocations.txt"
    pipeline_run_all "$TEST_DIR/worker" "$TEST_DIR/project" "$TEST_DIR/worker/workspace" ""

    assert_file_exists "$TEST_DIR/worker/step-config.json" "Step config should be written"

    local max_turns
    max_turns=$(jq -r '.max_turns' "$TEST_DIR/worker/step-config.json")
    assert_equals "10" "$max_turns" "Step config should contain max_turns"
}

# =============================================================================
# Test: Missing workspace aborts pipeline
# =============================================================================
test_pipeline_aborts_on_missing_workspace() {
    _create_pipeline "$TEST_DIR/pipeline.json" '{
        "name": "test-missing-ws",
        "steps": [
            {"id": "step-1", "agent": "agent-1"}
        ]
    }'

    unset _PIPELINE_RUNNER_LOADED 2>/dev/null || true
    source "$WIGGUM_HOME/lib/pipeline/pipeline-runner.sh"

    : > "$TEST_DIR/agent_invocations.txt"
    local exit_code=0
    pipeline_run_all "$TEST_DIR/worker" "$TEST_DIR/project" "$TEST_DIR/nonexistent-workspace" "" || exit_code=$?

    assert_equals "1" "$exit_code" "Should return 1 when workspace doesn't exist"
}

# =============================================================================
# Test: Activity log events are emitted for steps
# =============================================================================
test_pipeline_emits_activity_events() {
    _create_pipeline "$TEST_DIR/pipeline.json" '{
        "name": "test-activity",
        "steps": [
            {"id": "logged-step", "agent": "agent-logged"}
        ]
    }'

    unset _PIPELINE_RUNNER_LOADED 2>/dev/null || true
    source "$WIGGUM_HOME/lib/pipeline/pipeline-runner.sh"

    : > "$TEST_DIR/agent_invocations.txt"
    pipeline_run_all "$TEST_DIR/worker" "$TEST_DIR/project" "$TEST_DIR/worker/workspace" ""

    local activity_log="$TEST_DIR/project/.ralph/logs/activity.jsonl"
    assert_file_exists "$activity_log" "Activity log should exist"
    assert_file_contains "$activity_log" '"event":"step.started"' "Should log step.started"
    assert_file_contains "$activity_log" '"event":"step.completed"' "Should log step.completed"
    assert_file_contains "$activity_log" 'logged-step' "Should reference step ID"
}

# =============================================================================
# Run all tests
# =============================================================================
run_test test_pipeline_runs_steps_in_order
run_test test_pipeline_enabled_by_skips
run_test test_pipeline_enabled_by_runs
run_test test_pipeline_depends_on_skips_on_fail
run_test test_pipeline_blocking_failure_halts
run_test test_pipeline_nonblocking_failure_continues
run_test test_pipeline_start_from_step
run_test test_pipeline_writes_step_config
run_test test_pipeline_aborts_on_missing_workspace
run_test test_pipeline_emits_activity_events

print_test_summary
exit_with_test_result
