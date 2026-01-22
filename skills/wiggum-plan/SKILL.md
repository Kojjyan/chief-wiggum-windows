| name | description |
|------|-------------|
| wiggum-plan | Create implementation plans by exploring the codebase and designing an approach. Planning only - never implements. Always writes plan to `.ralph/plans/TASK-ID.md`. |

# Wiggum Plan

## Purpose

Create implementation plans by exploring the codebase and designing an approach. This skill is for **planning only** - it never implements code.

## Input

A task ID from `.ralph/kanban.md` (e.g., `TASK-015`, `FEATURE-042`).

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
4. **READ-ONLY exploration** - Only modify the plan file itself

## Core Workflow

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

## Example

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

## Key Principles

1. **Research before questions** - Explore codebase first, ground questions in findings
2. **Iterate freely** - Multiple rounds of explore → ask → explore is expected
3. **Be specific** - Reference actual file paths, function names, line numbers
4. **Always write plan** - Session must end with `.ralph/plans/TASK-ID.md`
5. **Never implement** - Planning only, no code changes

## Progressive Disclosure

This SKILL.md contains the core workflow. For detailed guidance:
- **Plan format**: references/plan-format.md
- **Exploration strategies**: references/exploration-strategies.md
- **Question patterns**: references/question-patterns.md
