#!/usr/bin/env bash
# Ralph Wiggum Loop - Self-prompting execution pattern

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/task-parser.sh"
source "$SCRIPT_DIR/logger.sh"

ralph_loop() {
    local prd_file="$1"                    # Worker's PRD file
    local agent_file="$2"                  # Agent definition
    local workspace="$3"                   # Worker's git worktree
    local max_iterations="${4:-50}"
    local iteration=0

    log "Ralph loop starting for $prd_file"

    while [ $iteration -lt $max_iterations ]; do
        # Exit if all tasks complete
        if ! has_incomplete_tasks "$prd_file"; then
            log "Worker completed all tasks in $prd_file"
            break
        fi

        # Build prompt referencing the PRD
        local prompt="Read $prd_file, find next incomplete task (- [ ]), execute it completely, then mark it complete (- [x])"

        log_debug "Iteration $iteration: Executing Claude Code"

        # Execute Claude Code autonomously in worker's workspace
        cd "$workspace" || exit 1
        claude code \
            --dangerously-skip-permissions \
            --agent-file "$agent_file" \
            --setting-sources "project,local" \
            --print \
            --output-format json \
            "$prompt" 2>&1 | tee -a "$workspace/../worker.log"

        iteration=$((iteration + 1))
        sleep 2  # Prevent tight loop
    done

    if [ $iteration -ge $max_iterations ]; then
        log_error "Worker reached max iterations ($max_iterations) without completing all tasks"
        return 1
    fi

    log "Worker finished after $iteration iterations"
    return 0
}
