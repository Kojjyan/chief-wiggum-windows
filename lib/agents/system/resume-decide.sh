#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# AGENT METADATA
# =============================================================================
# AGENT_TYPE: resume-decide
# AGENT_DESCRIPTION: Analyzes previous worker conversation logs and worker.log
#   to decide which step to resume from (or ABORT). Produces resume instructions
#   for the resumed worker with context about what was accomplished and what
#   needs to happen next.
# REQUIRED_PATHS:
#   - conversations : Directory with converted conversation markdown files
#   - worker.log    : Phase-level status log from previous run
# OUTPUT_FILES:
#   - resume-step.txt         : Contains the step name to resume from (or ABORT)
#   - resume-instructions.md  : Context and guidance for the resumed worker
#   - resume-result.json      : Contains PASS or FAIL
# =============================================================================

# Source base library and initialize metadata
source "$WIGGUM_HOME/lib/core/agent-base.sh"
agent_init_metadata "system.resume-decide" "Analyzes logs to decide resume step"

# Required paths before agent can run
agent_required_paths() {
    echo "conversations"
    echo "worker.log"
}

# Output files that must exist (non-empty) after agent completes
# resume-step.txt is a special control file read by the pipeline directly
agent_output_files() {
    echo "resume-step.txt"
}

# Global variable to track report path across functions
declare -g _RESUME_DECIDE_REPORT_PATH=""

# Source dependencies
agent_source_core
agent_source_once

# Source pipeline loader for dynamic config reading
source "$WIGGUM_HOME/lib/pipeline/pipeline-loader.sh"

# Load pipeline configuration and cache step info for prompt generation
# Sets _PIPELINE_STEPS array with step IDs in order
_load_pipeline_config() {
    local project_dir="${1:-$WIGGUM_HOME}"

    # Try to resolve and load pipeline config
    local pipeline_path
    pipeline_path=$(pipeline_resolve "$project_dir" "" "")

    if [ -n "$pipeline_path" ] && [ -f "$pipeline_path" ]; then
        pipeline_load "$pipeline_path" 2>/dev/null || pipeline_load_builtin_defaults
    else
        pipeline_load_builtin_defaults
    fi
}

# Get an agent's execution mode from its .md file
# Returns: mode string (ralph_loop, once, resume) or empty if not found
_get_agent_mode() {
    local agent_type="$1"
    local agent_path="${agent_type//./\/}"
    local md_file="$WIGGUM_HOME/lib/agents/${agent_path}.md"

    if [ ! -f "$md_file" ]; then
        echo ""
        return
    fi

    # Extract just the frontmatter and mode field
    local in_frontmatter=false
    local mode=""
    while IFS= read -r line; do
        if [ "$line" = "---" ]; then
            if [ "$in_frontmatter" = true ]; then
                break  # End of frontmatter
            fi
            in_frontmatter=true
            continue
        fi
        if [ "$in_frontmatter" = true ]; then
            if [[ "$line" =~ ^mode:[[:space:]]*(.+)$ ]]; then
                mode="${BASH_REMATCH[1]}"
                # Remove quotes if present
                mode="${mode#\"}"
                mode="${mode%\"}"
                break
            fi
        fi
    done < "$md_file"

    echo "${mode:-ralph_loop}"  # Default to ralph_loop if not specified
}

# Generate the "Pipeline Steps" table dynamically from loaded pipeline
# Returns markdown table via stdout
_generate_steps_table() {
    local step_count
    step_count=$(pipeline_step_count)

    echo "| # | Step | Agent | Special Handling |"
    echo "|---|------|-------|------------------|"

    local i=0
    local step_num=1
    while [ "$i" -lt "$step_count" ]; do
        local step_id agent is_readonly enabled_by special=""
        step_id=$(pipeline_get "$i" ".id")
        agent=$(pipeline_get "$i" ".agent")
        is_readonly=$(pipeline_get "$i" ".readonly" "false")
        enabled_by=$(pipeline_get "$i" ".enabled_by" "")

        # Skip disabled-by-default steps in the table
        if [ -n "$enabled_by" ]; then
            i=$((i + 1))
            continue
        fi

        # Determine special handling notes
        local agent_mode
        agent_mode=$(_get_agent_mode "$agent")
        if [ "$agent_mode" = "ralph_loop" ]; then
            # ralph_loop agents maintain state via summaries; must restart from beginning
            special="Cannot resume mid-step"
        elif [ "$is_readonly" = "true" ]; then
            special="Read-only"
        fi

        echo "| $step_num | \`$step_id\` | $agent | $special |"
        step_num=$((step_num + 1))
        i=$((i + 1))
    done
}

# Generate the "Decision Criteria" section
# Returns markdown via stdout
_generate_decision_criteria() {
    cat << 'EOF'
| Scenario | Decision |
|----------|----------|
| PRD has incomplete `- [ ]` tasks | First step marked "Cannot resume mid-step" |
| PRD says complete but workspace diff contradicts claims | First step marked "Cannot resume mid-step" |
| A step never ran or has no result file | That step |
| A step produced FAIL that needs retry | That step |
| All phases complete with outputs | `ABORT` |
| Fundamental issue (impossible task, repeated failures, bad PRD) | `ABORT` |
EOF
}

# Main entry point
agent_run() {
    local worker_dir="$1"
    local project_dir="$2"
    # $3 is max_iterations (unused — this agent runs once)
    local max_turns="${4:-25}"

    # Setup logging to worker.log
    export LOG_FILE="$worker_dir/worker.log"

    # Extract worker info for logging
    local worker_id
    worker_id=$(basename "$worker_dir")
    local task_id
    task_id=$(echo "$worker_id" | sed -E 's/worker-([A-Za-z]{2,10}-[0-9]{1,4})-.*/\1/' || echo "")
    local start_time
    start_time=$(date -Iseconds)

    # Log header
    log_section "RESUME-DECIDE"
    log_kv "Agent" "system.resume-decide"
    log_kv "Worker ID" "$worker_id"
    log_kv "Task ID" "$task_id"
    log_kv "Worker Dir" "$worker_dir"
    log_kv "Started" "$start_time"

    log "Analyzing previous run..."

    # Load pipeline configuration for dynamic prompt generation
    _load_pipeline_config "$project_dir"

    # Create standard directories
    agent_create_directories "$worker_dir"

    # Set up context for epoch-named results
    agent_setup_context "$worker_dir" "$worker_dir" "$project_dir"

    # Build a lightweight user prompt with file paths for the agent to explore
    local user_prompt
    user_prompt=$(_build_user_prompt "$worker_dir")

    # Run Claude with tool access so it can read the files itself
    # Create run-namespaced log directory (unified agent interface)
    local step_id="${WIGGUM_STEP_ID:-resume-decide}"
    local run_epoch
    run_epoch=$(date +%s)
    local run_id="${step_id}-${run_epoch}"
    mkdir -p "$worker_dir/logs/$run_id"
    local log_file="$worker_dir/logs/$run_id/${step_id}-0-${run_epoch}.log"

    local workspace="$worker_dir"
    [ -d "$worker_dir/workspace" ] && workspace="$worker_dir/workspace"

    run_agent_once "$workspace" \
        "$(_get_system_prompt "$worker_dir")" \
        "$user_prompt" \
        "$log_file" \
        "$max_turns"

    local agent_exit=$?

    if [ $agent_exit -ne 0 ]; then
        log_warn "Resume-decide agent exited with code $agent_exit"
    fi

    # Extract <step> and <instructions> from Claude's output
    local step instructions
    step=$(_extract_tag_content_from_stream_json "$log_file" "step") || true
    instructions=$(_extract_tag_content_from_stream_json "$log_file" "instructions") || true

    # Default to ABORT if no step extracted
    if [ -z "$step" ]; then
        log_error "No <step> tag found in resume-decide output"
        step="ABORT"
        instructions="${instructions:-Resume-decide agent did not produce a valid step decision.}"
    fi

    # Write outputs
    echo "$step" > "$worker_dir/resume-step.txt"
    if [ -z "$instructions" ]; then
        instructions="Resuming from step: $step. No detailed instructions available."
    fi
    _RESUME_DECIDE_REPORT_PATH=$(agent_write_report "$worker_dir" "$instructions")

    log "Resume decision: $step"

    # Log completion footer
    log_subsection "RESUME-DECIDE COMPLETED"
    log_kv "Decision" "$step"
    log_kv "Finished" "$(date -Iseconds)"

    # Both resume and abort are successful decisions
    agent_write_result "$worker_dir" "PASS" "$(printf '{"resume_step":"%s","report_file":"%s"}' "$step" "${_RESUME_DECIDE_REPORT_PATH:-}")"

    return 0
}

# System prompt for the resume-decide agent
_get_system_prompt() {
    local worker_dir="$1"

    cat << EOF
RESUME DECISION AGENT:

You determine where an interrupted worker should resume from. You do NOT fix issues - only analyze and decide.

WORKER DIRECTORY: $worker_dir

## Core Principle: EVIDENCE OVER ASSUMPTIONS

Trust nothing about the worker's state without verifying it in the logs and filesystem.
A phase claiming success means nothing if its output files are missing.
An interrupted phase needs evidence of WHERE it stopped, not just THAT it stopped.

## Worker Directory Layout

\`\`\`
$worker_dir/
├── worker.log           ← Phase-level status log (YOUR PRIMARY EVIDENCE)
├── prd.md               ← Task requirements (check completion status)
├── workspace/           ← Code changes (PRESERVED - do not modify)
├── conversations/       ← Converted conversation logs from previous run
│   ├── execution-*.md   ← Main work loop conversations
│   ├── audit-*.md       ← Security audit conversations
│   ├── test-*.md        ← Test coverage conversations
│   └── ...              ← Other sub-agent conversations
├── logs/                ← Raw JSON stream logs (DO NOT READ - too large)
├── summaries/           ← Iteration summaries
├── results/             ← Phase result files (PASS/FAIL/FIX/etc.)
└── reports/             ← Phase report files
\`\`\`

## Pipeline Steps (in execution order)

$(_generate_steps_table)

## Phase Completion Evidence

| Phase | Log Pattern (in worker.log) | Output File |
|-------|---------------------------|-------------|
| execution | "Task completed successfully" or "Ralph loop finished" | summaries/summary.txt |
| audit | "Security audit result: PASS\|FIX\|FAIL" | results/*-security-audit-result.json |
| test | "Test coverage result: PASS\|FAIL\|SKIP" | results/*-test-coverage-result.json |
| docs | "Documentation writer result:" | results/*-documentation-writer-result.json |
| validation | "Validation review completed with result:" | results/*-validation-review-result.json |
| finalization | "PR created:" or "Commit created" | results/*-system.task-worker-result.json |

## Git Restrictions (CRITICAL)

You are a READ-ONLY analyst. The workspace contains uncommitted work that MUST NOT be destroyed.

**FORBIDDEN (will corrupt the workspace):**
- \`git checkout\`, \`git stash\`, \`git reset\`, \`git clean\`, \`git restore\`
- \`git commit\`, \`git add\`
- Any write operation to workspace/

**ALLOWED (read-only):**
- \`git status\`, \`git diff\`, \`git log\`, \`git show\`
- Reading any file in the worker directory
EOF
}

# Build user prompt — structured methodology matching validation-review/security-audit patterns
_build_user_prompt() {
    local worker_dir="$1"

    # List available conversation files for the agent's awareness
    local conv_files=""
    if [ -d "$worker_dir/conversations" ]; then
        conv_files=$(ls "$worker_dir/conversations/"*.md 2>/dev/null | sort || true)
    fi

    # List result files that exist (epoch-named JSON results)
    local result_files=""
    result_files=$(ls "$worker_dir/results/"*-result.json 2>/dev/null | sort || true)

    cat << EOF
RESUME ANALYSIS TASK:

Determine where this interrupted worker should resume from. Trust nothing - verify everything.

## Step 1: Establish Ground Truth

Read the worker.log to understand what phases actually ran:

\`\`\`
$worker_dir/worker.log
\`\`\`

For EACH phase, look for:
- **Start marker**: "Running security audit..." / "Running test generation..." / etc.
- **Completion marker**: "result: PASS" / "result: FAIL" / etc.
- **Error markers**: "ERROR" / non-zero exit codes / missing output

## Step 2: Verify Phase Outputs

Cross-reference log claims against actual output files:

$(if [ -n "$result_files" ]; then
    echo "Result files found:"
    echo "$result_files" | while read -r f; do echo "- $f"; done
else
    echo "No result files found (phases may not have completed)."
fi)

For each phase that claims completion in the log, verify its output file EXISTS and is NON-EMPTY.
A phase is NOT complete if its output file is missing, even if the log says it ran.

## Step 3: Check PRD Completion Status

\`\`\`
$worker_dir/prd.md
\`\`\`

Count:
- \`- [x]\` tasks (completed)
- \`- [ ]\` tasks (incomplete)
- \`- [*]\` tasks (blocked/failed)

If ANY tasks are \`- [ ]\`, execution is NOT complete.

## Step 4: Verify Workspace Matches Claims

If execution appears complete, verify the workspace reflects what was claimed:

\`\`\`bash
cd $worker_dir/workspace && git diff --name-only   # What files actually changed
cd $worker_dir/workspace && git diff --stat         # Summary of changes
\`\`\`

Cross-reference against:
- The PRD task descriptions (what SHOULD have been modified)
- The summary file (summaries/summary.txt - what was CLAIMED to be modified)
- Conversation logs (what the agent SAID it did)

For each claimed modification:
1. **Does the file appear in git diff?** If not, the change was never made or was reverted
2. **Does the diff content match the description?** A file listed as "added new endpoint" should contain route/handler code, not just a comment
3. **Are claimed new files actually present?** Check \`git status\` for untracked files

If workspace state contradicts claims (files missing, changes don't match descriptions), execution is NOT truly complete — resume from \`execution\`.

## Step 5: Identify the Interruption Point

The resume step is the EARLIEST phase that:
- Started but did not produce its output file, OR
- Never started (no log entry), OR
- Produced a FAIL/error result that needs retry, OR
- Claims completion but workspace evidence contradicts it

## Step 6: Gather Context for Instructions

If resuming from a post-execution step, read the relevant conversation logs for context:

$(if [ -n "$conv_files" ]; then
    echo "Available conversation logs:"
    echo "$conv_files" | while read -r f; do echo "- $f"; done
else
    echo "No conversation logs found."
fi)

Read ONLY the conversations relevant to understanding what was accomplished (not the failed phase's log).

## Decision Criteria

$(_generate_decision_criteria)

## Common Mistakes to Avoid

- **Don't trust PRD checkboxes alone** — verify workspace diff actually contains the claimed changes
- **Don't resume from a post-execution step if the diff is empty** — execution didn't actually produce work
- **Don't skip a phase** — always resume from the EARLIEST incomplete phase
- **Don't assume a phase ran** just because the next phase started (it may have been skipped)
- **Don't read logs/ directory** — these are raw JSON streams that will exhaust your context

## Output Format

<step>STEP_NAME</step>

<instructions>
## What Was Accomplished

[Bullet points of completed work, with specific files modified and patterns used]

## Current State

[Description of workspace state: what code exists, what's been committed vs uncommitted]

## What Needs to Happen Now

[Specific guidance for the resumed phase:
- If execution: which PRD tasks remain, what patterns to follow
- If audit/test/docs/validation: context about what was implemented
- If finalization: what to commit, branch naming, PR description context]

## Warnings

[Issues from the previous run to be aware of:
- Errors encountered
- Partial work that may need cleanup
- Patterns or decisions that should be maintained]
</instructions>

The <step> tag MUST be exactly one of the pipeline step IDs shown in the table above, or ABORT
EOF
}

