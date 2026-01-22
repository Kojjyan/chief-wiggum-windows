| name | description |
|------|-------------|
| wiggum-ideas | Explore codebase and perform market research to generate new task ideas. Combines technical analysis with external research to identify improvements, features, and opportunities. |

# Wiggum Ideas

## Purpose

Explore the codebase and perform market research to generate new task ideas for the kanban. This skill combines technical analysis with external research to identify improvements, features, and opportunities.

## Input

Optional focus area (e.g., "performance", "security", "user experience", "competitive features").

## When This Skill is Invoked

**Manual invocation:**
- When looking for improvements or new features
- During sprint planning or roadmap sessions
- After user feedback indicates gaps
- To identify technical debt or security issues

**Typical flow:**
1. `/wiggum-ideas` generates ideas
2. User selects ideas to pursue
3. `/kanban` formalizes selected ideas as tasks
4. `/wiggum-plan` creates detailed plans for complex tasks

## Critical Rules

1. **Research before suggesting** - Don't generate ideas blindly; base them on findings
2. **Consider existing work** - Check kanban for related tasks and avoid duplicates
3. **Reasonable task sizing** - Ideas should be actionable, not vague wish lists
4. **Categorize ideas** - Group by type (quick win, feature, tech debt, security)

## Core Workflow

### Phase 1: Gather Context

**Check existing kanban:**
- Read `.ralph/kanban.md` to understand current priorities
- Note in-progress and pending tasks
- Identify gaps in the current roadmap

**Ask for focus area using AskUserQuestion:**

**AskUserQuestion Format:**
```
- question: Clear, specific question ending with ?
- header: Short label (max 12 chars)
- multiSelect: true/false as appropriate
- options: 2-4 specific choices
  - label: Concise choice text (1-5 words)
  - description: What this focus area covers
```

### Phase 2: Explore and Research (iterative)

This phase may repeat to gather comprehensive insights.

**Analyze the codebase:**
- **Glob/Grep/Read**: Understand current architecture
- Look for: TODO comments, FIXME notes, deprecated patterns
- Identify: Technical debt, performance bottlenecks, missing tests
- Check: Security patterns, error handling, logging

**Perform market research:**
- **WebSearch**: Research competitors, industry trends, best practices
- Look for: Features users expect, emerging patterns, security advisories
- Identify: Opportunities to differentiate, standards to adopt

**Ask clarifying questions:**
- What areas are highest priority?
- Any specific pain points reported?
- Constraints (time, resources, technology)?

**Iterate:** Research more based on answers.

### Phase 3: Generate and Categorize Ideas

For each idea, determine:
- What problem does this solve?
- How does it fit existing architecture?
- Complexity and effort estimate
- Dependencies on existing tasks

**Categories:**
- **Quick wins**: Low effort, high impact
- **Features**: New user-facing functionality
- **Tech debt**: Maintainability/performance improvements
- **Security**: Fixes or hardening
- **Infrastructure**: DevOps, tooling, CI/CD

### Phase 4: Present and Confirm

Present ideas with rationale, then use AskUserQuestion to select which to pursue.

```
questions:
  - question: Which ideas should we add to the kanban?
    header: Select ideas
    multiSelect: true
    options:
      - label: Idea 1 name
        description: Brief rationale and effort estimate
      - label: Idea 2 name
        description: Brief rationale and effort estimate
```

For selected ideas, offer to invoke `/kanban` to create properly formatted tasks.

## Example

**User**: `/wiggum-ideas security`

**Assistant**: I'll explore the codebase and research security best practices. Let me start with the current kanban.

*[Reads .ralph/kanban.md]*

Found 15 tasks. TASK-022 (HTTPS redirect) is pending. No other security tasks.

*[Uses AskUserQuestion]*
```
questions:
  - question: What security aspects should I focus on?
    header: Focus
    multiSelect: true
    options:
      - label: Authentication
        description: Login, tokens, session management
      - label: API security
        description: Rate limiting, input validation, headers
      - label: Dependencies
        description: Vulnerability scanning, updates
      - label: Data protection
        description: Encryption, PII handling, GDPR
```

**User selects**: Authentication, API security

**Assistant**: Focusing on auth and API security. Let me explore...

*[Uses Grep to find auth patterns]*
*[Uses Read to examine auth implementation]*

Found:
- JWT auth exists, no refresh token rotation
- No rate limiting on API endpoints
- Missing security headers (CSP, HSTS)

*[WebSearch: "JWT security best practices 2026"]*
*[WebSearch: "API security OWASP recommendations"]*

Research findings:
- OWASP recommends refresh token rotation
- Rate limiting is essential for auth endpoints
- Security headers block common attacks

Here are my ideas:

### Quick Wins
1. **Configure security headers** - Add helmet.js for CSP, HSTS, X-Frame-Options (Low effort)
2. **Add rate limiting to auth** - Prevent brute force attacks (Low effort)

### Features
3. **Implement refresh token rotation** - Industry standard, prevents token theft (Medium effort)
4. **Add security audit logging** - Track auth events for incident investigation (Medium effort)

### Tech Debt
5. **Audit JWT configuration** - Verify algorithm strength, expiry settings (Low effort)

*[Uses AskUserQuestion]*
```
questions:
  - question: Which ideas should we add to the kanban?
    header: Select
    multiSelect: true
    options:
      - label: Security headers
        description: Quick win, blocks common attacks
      - label: Rate limiting
        description: Quick win, prevents brute force
      - label: Token rotation
        description: Medium effort, industry standard
      - label: Audit logging
        description: Medium effort, enables investigation
```

**User selects**: Security headers, Rate limiting, Token rotation

**Assistant**: I'll create kanban tasks for these 3 ideas.

*[Invokes /kanban skill or generates tasks directly]*

Would you like me to run `/kanban` to create properly formatted tasks with dependencies, or should I generate them here?

## Key Principles

1. **Research first** - Explore codebase and web before generating ideas
2. **Ground in findings** - Every idea should have supporting evidence
3. **Avoid duplicates** - Check kanban for existing related tasks
4. **Categorize clearly** - Help user understand effort vs impact
5. **Actionable output** - Ideas should be convertible to kanban tasks

## Progressive Disclosure

This SKILL.md contains the core workflow. For detailed guidance:
- **Research strategies**: references/research-strategies.md
- **Categorization patterns**: references/categorization-patterns.md
- **Question patterns**: references/question-patterns.md
