#!/usr/bin/env bash
# Ralph Wiggum Loop - Self-prompting execution pattern with controlled context

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/task-parser.sh"
source "$SCRIPT_DIR/logger.sh"

# Extract clean text from Claude CLI stream-JSON output
# Filters out JSON and returns only assistant text responses
extract_summary_text() {
    local input="$1"

    # Extract text from JSON lines with type:"assistant" and text content
    echo "$input" | grep '"type":"assistant"' | \
        jq -r 'select(.message.content[]? | .type == "text") | .message.content[] | select(.type == "text") | .text' 2>/dev/null | \
        grep -v '^$'
}

ralph_loop() {
    local prd_file="$1"                    # Worker's PRD file (absolute path)
    local agent_file="$2"                  # Agent definition
    local workspace="$3"                   # Worker's git worktree
    local max_iterations="${4:-20}"
    local max_turns_per_session="${5:-50}" # Limit turns to control context window
    local iteration=0

    # Record start time
    local start_time=$(date +%s)
    echo "WORKER_START_TIME=$start_time" >> "../worker.log"

    log "Ralph loop starting for $prd_file (max $max_turns_per_session turns per session)"

    # Change to workspace BEFORE the loop
    cd "$workspace" || exit 1

    # Create logs subdirectory for detailed iteration logs
    mkdir -p "../logs"

    # Convert PRD file to relative path from workspace
    local prd_relative="../prd.md"

    # Track the last session ID for final summary
    local last_session_id=""

    while [ $iteration -lt $max_iterations ]; do
        # Exit if all tasks complete
        if ! has_incomplete_tasks "$prd_file"; then
            log "Worker completed all tasks in $prd_file"
            break
        fi

        # Generate unique session ID for this iteration
        local session_id=$(uuidgen)
        last_session_id="$session_id"

        local sys_prompt="Your working directory is $workspace. Do NOT directly or indirectly cd into, read, or modify files outside this directory."
        local user_prompt="Read @$prd_relative, find the next incomplete task (- [ ]), execute it completely within your working directory, then mark it as complete (- [x]) by editing the PRD file. If you are unable to complete the task, mark it as failed (- [*]) by editing the PRD file."

        # Add context from previous iterations if available
        if [ $iteration -gt 0 ] && [ -f "../worker.log" ]; then
            user_prompt="$user_prompt

For context on previous work in this session, read ../worker.log which contains summaries of all previous iterations."
        fi

        log_debug "Iteration $iteration: Session $session_id (max $max_turns_per_session turns)"

        # Log iteration start to worker.log (clean format)
        {
            echo ""
            echo "=== ITERATION $iteration ==="
            echo "Session ID: $session_id"
            echo "Max turns: $max_turns_per_session"
            echo "PWD: $(pwd)"
            echo "=== WORK PHASE ==="
        } >> "../worker.log"

        log "Work phase starting (see logs/iteration-$iteration.log for details)"

        # PHASE 1: Work session with turn limit
        # Use --dangerously-skip-permissions to allow PRD edits (hooks still enforce workspace boundaries)
        # Redirect verbose output to iteration-specific file
        claude --verbose \
            --output-format stream-json \
            --plugin-dir "$WIGGUM_HOME/skills" \
            --append-system-prompt "$sys_prompt" \
            --session-id "$session_id" \
            --max-turns "$max_turns_per_session" \
            --dangerously-skip-permissions \
            -p "$user_prompt" > "../logs/iteration-$iteration.log" 2>&1

        local exit_code=$?
        log "Work phase completed (exit code: $exit_code)"

        # PHASE 2: If session hit turn limit (exit code 1), resume for summary
        if [ $exit_code -ne 0 ]; then
            log "Session $session_id hit turn limit, requesting summary"

            {
                echo "=== SUMMARY PHASE ==="
            } >> "../worker.log"

            local summary_prompt="Your task is to create a detailed summary of the conversation so far, paying close attention to the user's explicit requests and your previous actions.
This summary should be thorough in capturing technical details, code patterns, and architectural decisions that would be essential for continuing development work without losing context.

Before providing your final summary, wrap your analysis in <analysis> tags to organize your thoughts and ensure you've covered all necessary points. In your analysis process:

1. Chronologically analyze each message and section of the conversation. For each section thoroughly identify:
   - The user's explicit requests and intents
   - Your approach to addressing the user's requests
   - Key decisions, technical concepts and code patterns
   - Specific details like file names, full code snippets, function signatures, file edits, etc
2. Double-check for technical accuracy and completeness, addressing each required element thoroughly.

Your summary should include the following sections:

1. Primary Request and Intent: Capture all of the user's explicit requests and intents in detail
2. Key Technical Concepts: List all important technical concepts, technologies, and frameworks discussed.
3. Files and Code Sections: Enumerate specific files and code sections examined, modified, or created. Pay special attention to the most recent messages and include full code snippets where applicable and include a summary of why this file read or edit is important.
4. Problem Solving: Document problems solved and any ongoing troubleshooting efforts.
5. Pending Tasks: Outline any pending tasks that you have explicitly been asked to work on.
6. Current Work: Describe in detail precisely what was being worked on immediately before this summary request, paying special attention to the most recent messages from both user and assistant. Include file names and code snippets where applicable.
7. Optional Next Step: List the next step that you will take that is related to the most recent work you were doing. IMPORTANT: ensure that this step is DIRECTLY in line with the user's explicit requests, and the task you were working on immediately before this summary request. If your last task was concluded, then only list next steps if they are explicitly in line with the users request. Do not start on tangential requests without confirming with the user first.
8. If there is a next step, include direct quotes from the most recent conversation showing exactly what task you were working on and where you left off. This should be verbatim to ensure there's no drift in task interpretation.

Here's an example of how your output should be structured:

<example>
<analysis>
[Your thought process, ensuring all points are covered thoroughly and accurately]
</analysis>

<summary>
1. Primary Request and Intent:
   [Detailed description]

2. Key Technical Concepts:
   - [Concept 1]
   - [Concept 2]
   - [...]

3. Files and Code Sections:
   - [File Name 1]
      - [Summary of why this file is important]
      - [Summary of the changes made to this file, if any]
      - [Important Code Snippet]
   - [File Name 2]
      - [Important Code Snippet]
   - [...]

4. Problem Solving:
   [Description of solved problems and ongoing troubleshooting]

5. Pending Tasks:
   - [Task 1]
   - [Task 2]
   - [...]

6. Current Work:
   [Precise description of current work]

7. Optional Next Step:
   [Optional Next step to take]

</summary>
</example>

Please provide your summary based on the conversation so far, following this structure and ensuring precision and thoroughness in your response. "

            log "Requesting summary for session $session_id"

            # Capture full output to iteration summary file
            local summary_full=$(claude --resume "$session_id" --max-turns 2 \
                --dangerously-skip-permissions -p "$summary_prompt" 2>&1 | \
                tee "../logs/iteration-$iteration-summary.log")

            # Extract clean text from JSON stream
            local summary=$(extract_summary_text "$summary_full")

            # Append clean summary to worker.log
            {
                echo "--- Session $iteration Summary ---"
                echo "$summary"
                echo "--- End Summary ---"
                echo ""
            } >> "../worker.log"

            # Append summary to PRD changelog section
            {
                echo ""
                echo "## Session $iteration Changelog ($(date -u +"%Y-%m-%d %H:%M:%S UTC"))"
                echo ""
                echo "$summary"
                echo ""
            } >> "$prd_file"

            log "Summary appended to PRD and worker.log"
        fi

        iteration=$((iteration + 1))
        sleep 2  # Prevent tight loop
    done

    if [ $iteration -ge $max_iterations ]; then
        log_error "Worker reached max iterations ($max_iterations) without completing all tasks"
        return 1
    fi

    # PHASE 3: Generate final comprehensive summary for changelog
    if [ -n "$last_session_id" ]; then
        log "Generating final summary for changelog"

        {
            echo ""
            echo "=== FINAL SUMMARY PHASE ==="
        } >> "../worker.log"

        local summary_prompt="All tasks have been completed successfully. Please provide a short summary and a comprehensive summary of everything you accomplished in this work session for the changelog. Include:

1. **TL;DR**: A short summary of what you did in this session with concise bullet points
2. **What was implemented**: Detailed description of changes, new features, or fixes
3. **Files modified**: List key files that were created or modified
4. **Technical details**: Important implementation decisions, patterns used, or configurations added
5. **Testing/Verification**: How you verified the work was correct

Format the response as a detailed markdown summary suitable for a project changelog. Be specific and technical."

        # Capture full output to final summary log
        local summary_full=$(claude --resume "$last_session_id" --max-turns 3 \
            --dangerously-skip-permissions -p "$summary_prompt" 2>&1 | \
            tee "../logs/final-summary.log")

        # Extract clean text from JSON stream
        local final_summary=$(extract_summary_text "$summary_full")

        # Append clean summary to worker.log
        {
            echo "--- Final Summary ---"
            echo "$final_summary"
            echo "--- End Final Summary ---"
            echo ""
        } >> "../worker.log"

        # Save to summary.txt (for PR description)
        echo "$final_summary" > "../summary.txt"

        log "Final summary saved to summary.txt and worker.log"
    fi

    # Record end time
    local end_time=$(date +%s)
    echo "WORKER_END_TIME=$end_time" >> "../worker.log"

    log "Worker finished after $iteration iterations"
    return 0
}
