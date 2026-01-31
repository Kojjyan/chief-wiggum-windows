# Chief Wiggum

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Language-Bash-blue)](https://www.gnu.org/software/bash/)
[![Windows](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-green)](https://github.com)

**Chief Wiggum** is an agentic task runner that autonomously executes software engineering tasks using Claude Code. Define tasks in a Kanban board, and Chief Wiggum spawns isolated workers that implement features, run tests, and create pull requests.

![Chief Wiggum](docs/chief_wiggum.jpeg)

## Prerequisites

### All Platforms
- **Git** (2.20+)
- **Claude Code** (`claude` CLI installed and authenticated)
- **GitHub CLI** (`gh` installed and authenticated)
- **jq** (JSON processor)

### Linux/macOS
- **Bash 4.0+**
- **setsid** (macOS: `brew install util-linux`)

### Windows
- **Git for Windows** (provides Git Bash - required runtime)
- All commands must be run in **Git Bash**, not PowerShell or cmd

## Installation

### Windows

**Option A: PowerShell Installer**
```powershell
# Install prerequisites first
winget install jqlang.jq
winget install GitHub.cli
# Install Claude Code from https://docs.anthropic.com/en/docs/claude-code

# Close and reopen PowerShell, then run:
.\install.ps1
```

**Option B: Git Bash**
```bash
./install.sh
```

After installation, add to your `~/.bashrc`:
```bash
echo 'export PATH="$HOME/.claude/chief-wiggum/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Linux/macOS

```bash
./install.sh
echo 'export PATH="$HOME/.claude/chief-wiggum/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Run from Source (All Platforms)

```bash
export WIGGUM_HOME=$(pwd)
export PATH="$WIGGUM_HOME/bin:$PATH"
```

## Quick Start

> **Windows Users:** All commands below must be run in **Git Bash**.

### 1. Initialize

```bash
cd /path/to/your/project
wiggum init
```

Creates `.ralph/kanban.md` for task definitions.

### 2. Define Tasks

Edit `.ralph/kanban.md`:

```markdown
## TASKS

- [ ] **[TASK-001]** Add user authentication
  - Description: Implement JWT-based auth with login/logout endpoints
  - Priority: HIGH
  - Dependencies: none
```

Task markers:
- `[ ]` Pending
- `[=]` In Progress
- `[x]` Complete
- `[*]` Failed

### 3. Run

```bash
wiggum run                    # Start workers for pending tasks
wiggum run --max-workers 8    # Limit concurrent workers
```

### 4. Monitor

```bash
wiggum status          # Overview of all workers
wiggum monitor         # Live combined logs
wiggum monitor split   # Split pane per worker
```

### 5. Review

```bash
wiggum review list           # List open PRs
wiggum review pr 123 view    # View specific PR
wiggum review merge-all      # Merge all worker PRs
```

## Commands

| Command | Description |
|---------|-------------|
| `wiggum init` | Initialize project with `.ralph/` directory |
| `wiggum run` | Start workers for pending tasks |
| `wiggum status` | Show worker status overview |
| `wiggum monitor` | Live log viewer |
| `wiggum review` | PR management |
| `wiggum validate` | Validate kanban format |
| `wiggum clean` | Remove worker worktrees |
| `wiggum inspect` | Debug workers, pipelines, agents |

## How It Works

For each task, Chief Wiggum:

1. Creates an isolated **git worktree**
2. Generates a **PRD** from the task specification
3. Runs a **pipeline** of agents (execution → audit → test → docs → validation)
4. Creates a **Pull Request** with the changes

Workers are fully isolated and can run in parallel without conflicts.

## Configuration

### Pipeline

Customize the agent pipeline in `config/pipeline.json`. See [docs/PIPELINE-SCHEMA.md](docs/PIPELINE-SCHEMA.md).

### Project Settings

Override defaults in `.ralph/config.json`:

```json
{
  "max_workers": 4,
  "max_iterations": 20,
  "max_turns": 50
}
```

## Platform Notes

### Windows
- Uses `disown` instead of `setsid` for process isolation
- Uses `tasklist`/`taskkill` for process management
- Uses directory-based file locking instead of `flock`
- Git Bash provides Unix compatibility layer

### Linux/macOS
- Uses native `setsid` and `flock`
- Full POSIX compatibility

## Documentation

- [Pipeline Schema](docs/PIPELINE-SCHEMA.md) - Configure agent pipelines
- [Architecture](docs/ARCHITECTURE.md) - Developer guide and internals
- [Agent Development](docs/AGENT_DEV_GUIDE.md) - Writing custom agents

## License

MIT
