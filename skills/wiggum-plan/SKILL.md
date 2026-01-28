| name | description |
|------|-------------|
| wiggum-plan | Create implementation plans by exploring the codebase and designing an approach. Planning only - never implements. Always writes plan to `.ralph/plans/TASK-ID.md`. |

# Wiggum Plan

## Purpose

Create implementation plans by exploring the codebase and designing an approach. This skill is for **planning only** - it never implements code.

## Input

**Mode 1 - Existing Task**: A task ID from `.ralph/kanban.md` (e.g., `TASK-015`, `FEATURE-042`).

**Mode 2 - New Task**: A description of work to be done (e.g., "Add user authentication with JWT"). When no valid task ID is provided, the skill will:
1. Create the task in `.ralph/kanban.md`
2. Then create the implementation plan

## When This Skill is Invoked

**Manual invocation:**
- Before implementing a complex task
- When a task needs architectural analysis
- To document approach before handing to a worker

**From other skills:**
- After `/kanban` creates tasks that need detailed planning

## Critical Rules

1. **NEVER implement** - This skill produces plans, not code
2. **ALWAYS write the plan file** - Every session must end with writing `.ralph/plans/TASK-ID.md`
3. **Multiple iterations allowed** - Explore, ask questions, explore more as needed
4. **READ-ONLY exploration** - Only modify the kanban file (when creating tasks) and plan file
5. **Create task when needed** - If no valid task ID is provided, create the task in kanban first

## Core Workflow

### Phase 0: Task Creation (when no task ID provided)

**Skip this phase if a valid task ID was provided.**

When the input is a description rather than a task ID:

**Analyze existing kanban:**
- Read `.ralph/kanban.md`
- Identify the highest task number for ID assignment
- Note existing dependencies and task prefixes used
- Check for similar/related pending tasks

**Clarify requirements with AskUserQuestion:**
- Scope: What should be included/excluded?
- Priority: How urgent is this work?
- Dependencies: Does this depend on existing tasks?

**Design the task:**
- Determine if it should be one task or multiple
- If multiple tasks needed, break down with proper dependencies (use Scope field for sub-items within a single task)
- Each task should be completable by one worker in one session

**Create the task in kanban:**
- Add properly formatted task entry to `.ralph/kanban.md`
- Include all required fields: Description, Priority, Dependencies
- Use optional fields (Scope, Acceptance Criteria) when helpful
- Confirm with user before writing via AskUserQuestion

For task format details, see `/kanban` skill references:
- Task format: `skills/kanban/references/task-format.md`
- Dependency patterns: `skills/kanban/references/dependency-patterns.md`
- Sizing guidelines: `skills/kanban/references/sizing-guidelines.md`

**After task creation, continue to Phase 1 with the newly created task ID.**

### Phase 1: Explore and Understand (iterative)

This phase may repeat multiple times until you have a complete picture.

**Read the task requirements:**
- Read `.ralph/kanban.md` and find the task entry for the given ID
- Extract Description, Scope, Acceptance Criteria, Dependencies
- Check dependent tasks to understand what they provide

**Explore the codebase (READ-ONLY):**
- **Glob**: Find files by pattern
- **Grep**: Search for code patterns, function names, imports
- **Read**: Examine specific files in detail
- **Bash** (read-only): `ls`, `git log`, `git diff`, `find`

Look for:
- Similar features as reference implementations
- Existing patterns and conventions
- Related code that will be affected
- Test patterns used in the project

**Ask clarifying questions using AskUserQuestion:**

**AskUserQuestion Format:**
```
- question: Clear, specific question ending with ?
- header: Short label (max 12 chars)
- multiSelect: false (unless choices aren't mutually exclusive)
- options: 2-4 specific choices grounded in codebase findings
  - label: Concise choice text (1-5 words)
  - description: Context from exploration (file paths, patterns found)
```

**Question types:**
- **Approach**: Which pattern should we follow?
- **Trade-offs**: Performance vs simplicity?
- **Scope clarification**: What edge cases to handle?
- **Integration**: How should this interact with X?

**Iterate:** After getting answers, explore more if needed. Repeat until complete understanding.

### Phase 2: Design the Solution

Consider:
- How does this fit the existing architecture?
- What are the trade-offs of different approaches?
- What dependencies exist between components?
- What could go wrong? Edge cases?
- How does the solution impact other in-progress and pending tasks?

### Phase 3: Write the Plan (REQUIRED)

**You MUST write the plan to `.ralph/plans/TASK-ID.md`** - this is not optional.

For plan structure and format, see references/plan-format.md.

## Examples

### Example 1: Planning an Existing Task

**User**: `/wiggum-plan TASK-015`

**Assistant**: I'll create an implementation plan for TASK-015. Let me read the task requirements first.

*[Reads .ralph/kanban.md]*

Found TASK-015:
```
- [ ] **[TASK-015]** Create auth routes (login/register)
  - Description: Create POST /auth/login and POST /auth/register endpoints
  - Priority: HIGH
  - Dependencies: TASK-013, TASK-014, TASK-010
```

Now exploring the codebase for existing patterns...

*[Uses Glob to find route files]*
*[Uses Read to examine src/routes/users.ts]*

Found route pattern using Express Router with controller separation.

*[Uses Grep to find validation patterns]*

Found validation using `express-validator` in existing routes.

*[Uses AskUserQuestion]*
```
questions:
  - question: Should registration require email verification?
    header: Email verify
    multiSelect: false
    options:
      - label: No verification
        description: User gets immediate access after registration
      - label: Email verification
        description: User must verify email before login (requires email service)
  - question: What password requirements?
    header: Password
    multiSelect: false
    options:
      - label: Minimum 8 chars
        description: Simple requirement, good UX
      - label: Complex rules
        description: Uppercase, lowercase, number, special char
  - question: Should failed logins be rate-limited?
    header: Rate limit
    multiSelect: false
    options:
      - label: Yes, use existing pattern
        description: Found rate-limiter in src/middleware/rate-limit.ts
      - label: No rate limiting
        description: Simpler but less secure
```

**User selects**: No verification, Minimum 8 chars, Yes use existing pattern

**Assistant**: Good. Let me verify the rate limiter integration...

*[Uses Read to examine src/middleware/rate-limit.ts]*

Confirmed rate limiter pattern. I have a complete picture.

*[Writes to .ralph/plans/TASK-015.md]*

I've saved the implementation plan to `.ralph/plans/TASK-015.md`. The plan covers:

- Route structure following `src/routes/users.ts` pattern
- Validation using `express-validator`
- Rate limiting using existing middleware
- Password hashing with bcrypt (min 8 chars)
- Integration with TASK-013 (JWT utils) and TASK-014 (auth middleware)

The plan is ready for a Chief Wiggum worker to execute.

### Example 2: Creating Task and Plan Together

**User**: `/wiggum-plan Add a dark mode toggle to the settings page`

**Assistant**: I'll help create and plan this feature. Since no task ID was provided, let me first analyze the existing kanban.

*[Reads .ralph/kanban.md]*

Found 15 tasks. Highest ID is TASK-015. TASK-012 (Settings page) is complete `[x]`. Using TASK- prefix.

*[Uses AskUserQuestion]*
```
questions:
  - question: What priority level for dark mode?
    header: Priority
    multiSelect: false
    options:
      - label: HIGH
        description: Important UX feature, blocking other work
      - label: MEDIUM
        description: Nice-to-have, not blocking other tasks
      - label: LOW
        description: Low priority enhancement
  - question: What should be included in dark mode scope?
    header: Scope
    multiSelect: true
    options:
      - label: Settings toggle
        description: UI toggle in settings page
      - label: System preference
        description: Auto-detect OS dark/light preference
      - label: Persist choice
        description: Remember user's selection across sessions
```

**User selects**: MEDIUM, Settings toggle, Persist choice

**Assistant**: I'll create a single task for this. Let me show you the proposed entry:

```markdown
- [ ] **[TASK-016]** Add dark mode toggle to settings page
  - Description: Add a toggle in settings to switch between light and dark themes with persistence
  - Priority: MEDIUM
  - Dependencies: TASK-012
  - Scope:
    - Add toggle switch component to settings page
    - Implement theme state management
    - Apply theme styles across the application
    - Persist theme preference in local storage
  - Acceptance Criteria:
    - Toggle changes theme immediately
    - Theme persists across page reloads
    - Theme persists across browser sessions
```

*[Uses AskUserQuestion]*
```
questions:
  - question: Add this task to .ralph/kanban.md?
    header: Confirm
    multiSelect: false
    options:
      - label: Yes, add task
        description: Add TASK-016 to kanban and continue to planning
      - label: Modify first
        description: I want to adjust something before adding
```

**User selects**: Yes, add task

**Assistant**: Added TASK-016 to kanban. Now let me explore the codebase to create the implementation plan...

*[Uses Glob to find settings components]*
*[Uses Read to examine src/pages/Settings.tsx]*
*[Uses Grep to find existing theme patterns]*

Found existing color variables in `src/styles/variables.css`. Settings page uses component library.

*[Uses AskUserQuestion]*
```
questions:
  - question: How should the theme be managed?
    header: Theme state
    multiSelect: false
    options:
      - label: React Context
        description: Found existing context pattern in src/context/
      - label: CSS variables
        description: Toggle CSS class on body, simpler approach
```

**User selects**: CSS variables

**Assistant**: Good choice for simplicity. Let me complete the plan...

*[Writes to .ralph/plans/TASK-016.md]*

I've created TASK-016 in kanban and saved the implementation plan to `.ralph/plans/TASK-016.md`. Summary:

- Task added to `.ralph/kanban.md` with MEDIUM priority
- Plan uses CSS variables approach with body class toggle
- Theme stored in localStorage for persistence
- Toggle component added to Settings page

## Key Principles

1. **Research before questions** - Explore codebase first, ground questions in findings
2. **Iterate freely** - Multiple rounds of explore → ask → explore is expected
3. **Be specific** - Reference actual file paths, function names, line numbers
4. **Always write plan** - Session must end with `.ralph/plans/TASK-ID.md`
5. **Never implement** - Planning only, no code changes
6. **Seamless task creation** - When no task ID provided, create task in kanban before planning
7. **Confirm before writing kanban** - Always ask user to confirm before adding tasks to kanban

## Progressive Disclosure

This SKILL.md contains the core workflow. For detailed guidance:
- **Plan format**: references/plan-format.md
- **Exploration strategies**: references/exploration-strategies.md
- **Question patterns**: references/question-patterns.md
