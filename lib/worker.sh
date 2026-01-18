#!/usr/bin/env bash
# Worker script - spawned by chief for each task

WORKER_DIR="$1"         # e.g., .ralph/workers/worker-TASK-001-12345
PROJECT_DIR="$2"        # Project root directory
CHIEF_HOME="${CHIEF_HOME:-$HOME/.claude/chief-wiggum}"

source "$CHIEF_HOME/lib/ralph-loop.sh"
source "$CHIEF_HOME/lib/logger.sh"

main() {
    log "Worker starting: $WORKER_ID for task $TASK_ID"

    setup_worker

    # Start Ralph loop for this worker's task
    if ralph_loop \
        "$WORKER_DIR/prd.md" \
        "$CHIEF_HOME/config/worker-agent.md" \
        "$WORKER_DIR/workspace" \
        50; then
        log "Worker $WORKER_ID completed successfully"
    else
        log_error "Worker $WORKER_ID failed or timed out"
    fi

    cleanup_worker
    log "Worker finished: $WORKER_ID"
}

setup_worker() {
    # Create git worktree for isolation
    cd "$PROJECT_DIR" || exit 1

    log_debug "Creating git worktree at $WORKER_DIR/workspace"
    git worktree add "$WORKER_DIR/workspace" HEAD 2>&1 | tee -a "$WORKER_DIR/worker.log"

    # Setup hooks
    export CLAUDE_HOOKS_CONFIG="$CHIEF_HOME/hooks/worker-hooks.json"
    export WORKER_ID
    export TASK_ID
}

cleanup_worker() {
    log "Cleaning up worker $WORKER_ID"

    # Save results
    if [ -d "$WORKER_DIR/workspace" ]; then
        # Copy any generated artifacts to results/
        mkdir -p "$PROJECT_DIR/.ralph/results/$TASK_ID"
        log "Copying results to .ralph/results/$TASK_ID/"
        cp -r "$WORKER_DIR/workspace/"* "$PROJECT_DIR/.ralph/results/$TASK_ID/" 2>/dev/null || true
    fi

    # Clean up git worktree
    cd "$PROJECT_DIR" || exit 1
    log_debug "Removing git worktree"
    git worktree remove "$WORKER_DIR/workspace" --force 2>&1 | tee -a "$WORKER_DIR/worker.log"

    # Mark task complete in kanban (simple sed)
    log "Marking task $TASK_ID as complete in kanban"
    sed -i "s/- \[ \] \*\*\[$TASK_ID\]\*\*/- [x] **[$TASK_ID]**/" "$PROJECT_DIR/.ralph/kanban.md"

    log "Worker $WORKER_ID completed task $TASK_ID"
}

main "$@"
