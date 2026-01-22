# Research Strategies Reference

## Codebase Analysis

### Finding Technical Debt
```bash
# TODO/FIXME comments
Grep: "TODO|FIXME|HACK|XXX"

# Deprecated patterns
Grep: "@deprecated|deprecate"

# Error suppression
Grep: "eslint-disable|@ts-ignore|noqa"
```

### Finding Security Issues
```bash
# Hardcoded secrets
Grep: "password.*=|secret.*=|api_key"

# SQL injection risks
Grep: "query.*\+|execute.*\+"

# Missing validation
Grep: "req\.body\.|req\.params\." # then check for validation
```

### Finding Performance Issues
```bash
# N+1 queries
Grep: "for.*await|\.map.*await"

# Missing indexes (check models)
Read: models/ directory, look for query patterns

# Large synchronous operations
Grep: "readFileSync|writeFileSync"
```

### Finding Missing Tests
```bash
# Compare source to test files
Glob: "src/**/*.ts"
Glob: "tests/**/*.test.ts"
# Look for untested modules
```

## Market Research

### WebSearch Queries

**Security:**
- "[framework] security best practices 2026"
- "OWASP top 10 [language]"
- "[library] known vulnerabilities"

**Features:**
- "[product type] must-have features"
- "[competitor] features comparison"
- "[industry] user expectations"

**Performance:**
- "[framework] performance optimization"
- "[database] query optimization"
- "web vitals improvement techniques"

**Architecture:**
- "[pattern] vs [pattern] trade-offs"
- "[framework] recommended architecture"
- "scaling [technology] best practices"

### Competitive Analysis

1. Identify main competitors
2. Search: "[competitor] features"
3. Search: "[competitor] vs [your product type]"
4. Look for feature gaps and differentiators

## Combining Findings

### Pattern: Gap Analysis
1. List current features (from codebase)
2. List expected features (from research)
3. Identify gaps
4. Prioritize by effort vs impact

### Pattern: Risk Assessment
1. Find potential issues (codebase)
2. Research severity (web)
3. Check if addressed in kanban
4. Prioritize by risk level

### Pattern: Modernization
1. Identify outdated patterns (codebase)
2. Research current best practices (web)
3. Assess migration effort
4. Propose incremental updates

## Iteration Guidelines

**When to iterate:**
- Found something that needs deeper investigation
- User answer reveals new area to explore
- Initial findings are inconclusive

**When to stop:**
- Have 3-5 solid ideas with evidence
- Further research yields diminishing returns
- User has indicated enough options
