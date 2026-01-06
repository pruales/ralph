# ralph

Minimal loop runner for Claude Code or Codex CLI. Ralph executes an agentic loop that works through a PRD (Product Requirements Document) one task at a time, committing progress as it goes.

## Learn More

- [Video: Ralph in Action](https://www.youtube.com/watch?v=_IK18goX4X8)
- [Article: The Ralph Pattern](https://ghuntley.com/ralph/)
- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

## How It Works

Ralph implements a simple but effective pattern for long-running AI agents:

```
┌─────────────────────────────────────────────────────────┐
│                     Ralph Loop                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   1. Read PRD (prd.json)                               │
│      ↓                                                  │
│   2. Pick highest-priority incomplete task             │
│      ↓                                                  │
│   3. Implement the task                                │
│      ↓                                                  │
│   4. Run tests/typecheck                               │
│      ↓                                                  │
│   5. Update PRD (mark task complete)                   │
│      ↓                                                  │
│   6. Append notes to progress.txt                      │
│      ↓                                                  │
│   7. Git commit                                        │
│      ↓                                                  │
│   8. Sleep, then repeat from step 1                    │
│      (until PRD complete or stopped)                   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

Each iteration is a fresh context—the agent reads the current state from files, does one unit of work, persists its progress, and exits. This prevents context bloat and makes the process resumable.

## Prompt Layering

Ralph builds the final prompt by layering multiple sources:

```
┌─────────────────────────────────────┐
│ 1. Base Prompt                      │  ← RALPH_PROMPT_FILE, or ./prompt.md, or built-in default
├─────────────────────────────────────┤
│ 2. Session Prompt (if using session)│  ← .agent/sessions/<name>/prompt.md
├─────────────────────────────────────┤
│ 3. Append File (if set)             │  ← RALPH_PROMPT_APPEND_FILE
└─────────────────────────────────────┘
```

File paths in the prompt use the `@/path/to/file` syntax that Claude Code and Codex recognize for file references.

## Quick Start

Install the global `ralph` wrapper:

```bash
./install.sh
```

Then use it from any repo:

```bash
# Simple mode: uses ./prompt.md or built-in prompt
ralph claude
# or
ralph codex
```

Stop with Ctrl+C, or create `.agent/STOP`.

## Sessions (Recommended)

Sessions keep your PRD, progress, and prompt organized per feature/project.

### Create a session

```bash
ralph init feature-x
```

This creates:
```
.agent/sessions/feature-x/
├── prd.json       # Task list with acceptance criteria
├── progress.txt   # Append-only log of work done
└── prompt.md      # Session-specific instructions
```

### Edit session files

**prd.json** - Define your tasks:
```json
[
  {
    "id": "add-login",
    "title": "Add login form",
    "description": "Users can sign in with email/password",
    "acceptance": [
      "Form renders on /login",
      "Invalid credentials show error",
      "Successful login redirects to /dashboard"
    ],
    "priority": "high",
    "passes": false
  }
]
```

**prompt.md** - Add context for the agent:
```markdown
Context anchors (read before coding):
- `specs/auth.md` (authentication requirements)
- `src/services/auth.ts` (existing auth code)

Build commands:
- TypeScript: `pnpm typecheck`
- Tests: `pnpm test`

Scope:
- Focus on `src/auth/` directory
- Do not modify database schema
```

### Run a session

```bash
ralph --session feature-x claude
# or
ralph --session feature-x codex
```

### Single iteration (for testing)

```bash
ralph --session feature-x --once claude
```

### List sessions

```bash
ralph list
```

## Debugging

Each run logs the built prompt for verification:

```
.agent/logs/claude_20260105_120000_prompt.md   # What was sent to the agent
.agent/logs/claude_20260105_120000.log         # Agent output
```

For sessions, logs go to `.agent/sessions/<name>/logs/`.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RALPH_PROMPT_FILE` | Override base prompt file | `./prompt.md` |
| `RALPH_PROMPT_APPEND_FILE` | Append extra instructions | (none) |
| `RALPH_PRD_FILE` | Override PRD path | `./plans/prd.json` |
| `RALPH_PROGRESS_FILE` | Override progress path | `./progress.txt` |
| `RALPH_SESSION` | Default session name | (none) |
| `RALPH_SLEEP_SECONDS` | Sleep between iterations | `10` |
| `RALPH_MAX_ITERATIONS` | Max iterations before stopping | (unlimited) |
| `RALPH_PROMISE_PATTERN` | Completion marker | `<promise>COMPLETE</promise>` |
| `RALPH_NOTIFY` | macOS notification on completion | `0` |
| `RALPH_NOTIFY_CMD` | Custom command on completion | (none) |

### Claude-specific

> **Caution:** Claude runs with `bypassPermissions` by default, which skips all permission prompts so the agent can run autonomously. If you're concerned about security, set `RALPH_CLAUDE_PERMISSION_MODE=default` to restore interactive approval prompts.

| Variable | Description | Default |
|----------|-------------|---------|
| `RALPH_CLAUDE_OUTPUT_FORMAT` | Output format | `stream-json` |
| `RALPH_CLAUDE_PERMISSION_MODE` | Permission mode | `bypassPermissions` |
| `RALPH_CLAUDE_PRETTY` | Pretty print results | `1` |
| `RALPH_CLAUDE_PARTIAL` | Include partial messages | `0` |

### Codex-specific

> **Caution:** Codex runs in YOLO mode by default (`--yolo`), which bypasses all approval prompts and sandboxing. This gives the agent full system access. If you're concerned about security, disable it with `RALPH_CODEX_YOLO=0` to use approval and sandbox controls instead.

| Variable | Description | Default |
|----------|-------------|---------|
| `RALPH_CODEX_YOLO` | Bypass approvals/sandbox | `1` |
| `RALPH_CODEX_APPROVAL` | Approval mode (when YOLO=0) | `never` |
| `RALPH_CODEX_SANDBOX` | Sandbox mode (when YOLO=0) | `workspace-write` |

## CLI Options

```bash
ralph <claude|codex>                      # Run loop
ralph --once <claude|codex>               # Single iteration
ralph --session <name> <claude|codex>     # Run with session
ralph --iterations <n> <claude|codex>     # Limit iterations
ralph --prd /path/to/prd.json <cli>       # Override PRD path
ralph --progress /path/to/progress.txt <cli>  # Override progress path
ralph init <name>                         # Create session
ralph list                                # List sessions
```

## Completion and Limits

- Ralph stops when the agent outputs `<promise>COMPLETE</promise>`
- Set `RALPH_MAX_ITERATIONS` or `--iterations <n>` to cap runs
- Create `.agent/STOP` (or `.agent/sessions/<name>/STOP`) to stop gracefully

## Ralph Planner Skill

The `ralph-planner` skill helps shape work into PRD tasks without running Ralph:

```bash
# Install to Claude Code
cp -r skills/ralph-planner ~/.claude/skills/

# Install to Codex
cp -r skills/ralph-planner ~/.codex/skills/
```

Then invoke with `/ralph-planner` in Claude Code or Codex.

## Updating

After pulling changes:

```bash
./install.sh
```

This re-copies `ralph.sh` to `~/.local/share/ralph/ralph.sh`.

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/cli-reference) (for `claude` mode)
- [Codex CLI](https://developers.openai.com/codex/cli) (for `codex` mode)
- `jq` (optional, for pretty-printed Claude output)
