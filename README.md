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
├── spec.md        # Combined: specs + task list + acceptance criteria
├── progress.txt   # Append-only log of work done
└── prompt.md      # Session-specific instructions and context anchors
```

### Edit session files

**spec.md** - Combined spec and task list:
```markdown
# Session: Auth Flow

## Overview
Implement user authentication with email/password login.

## Context & Requirements
- JWT-based session management
- Password must be hashed with bcrypt
- Failed logins rate-limited after 5 attempts

## Tasks

### ⬜ Task: add-login-form
**Priority:** high
**Status:** incomplete

Users can sign in with email/password.

**Acceptance:**
- [ ] Form renders on /login
- [ ] Invalid credentials show error
- [ ] Successful login redirects to /dashboard

---
```

**prompt.md** - Context anchors and instructions:
```markdown
# Context Anchors (read these first)
These files contain the source of truth:
- `spec.md` - session spec with all tasks
- `specs/auth.md` - authentication requirements
- `src/services/auth.ts` - existing auth code

# Build Commands
- TypeScript: `pnpm typecheck`
- Tests: `pnpm test --bail` (only show failures)

# Scope
- Focus on `src/auth/` directory
- Do NOT modify database schema
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

## Logging

Each run creates a single combined markdown file:

```
.agent/logs/claude_20260105_120000.md
```

The file contains:
- **Prompt** (only if changed from previous run)
- **Transcript** (full JSON stream of all tool calls and responses)
- **Summary** (for Codex runs)

For sessions, logs go to `.agent/sessions/<name>/logs/`.

**Log management:**
- Prompts are deduplicated (only saved when changed)
- Old logs (>1 day) are automatically compressed with gzip
- Use `ralph clean` to manually clean up

```bash
# Clean logs in default directory
ralph clean

# Clean logs for a specific session
ralph clean --session feature-x
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RALPH_PROMPT_FILE` | Override base prompt file | `./prompt.md` |
| `RALPH_PROMPT_APPEND_FILE` | Append extra instructions | (none) |
| `RALPH_SPEC_FILE` | Override spec.md path | `./spec.md` or session spec |
| `RALPH_PROGRESS_FILE` | Override progress path | `./progress.txt` |
| `RALPH_SESSION` | Default session name | (none) |
| `RALPH_SLEEP_SECONDS` | Sleep between iterations | `10` |
| `RALPH_MAX_ITERATIONS` | Max iterations before stopping | (unlimited) |
| `RALPH_PROMISE_PATTERN` | Completion marker | `<promise>COMPLETE</promise>` |
| `RALPH_SUPERVISOR_SCRIPT` | Executable script to check iterations | (none) |
| `RALPH_SUPERVISOR_NUDGE` | Nudge prompt when check fails | (none) |
| `RALPH_NOTIFY` | macOS notification on completion | `0` |
| `RALPH_NOTIFY_CMD` | Custom command on completion | (none) |
| `RALPH_COMPRESS_LOGS` | Gzip logs immediately after each run | `0` |

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
ralph --prd /path/to/spec.md <cli>        # Override spec path
ralph --progress /path/to/progress.txt <cli>  # Override progress path
ralph init <name>                         # Create session
ralph list                                # List sessions
ralph clean                               # Clean logs (remove empty, compress old)
ralph clean --session <name>              # Clean session logs
```

## Completion and Limits

- Ralph stops when the agent outputs `<promise>COMPLETE</promise>`
- Set `RALPH_MAX_ITERATIONS` or `--iterations <n>` to cap runs
- Create `.agent/STOP` (or `.agent/sessions/<name>/STOP`) to stop gracefully

## Supervisor Loop Pattern

Ralph supports an optional supervisor pattern for checking that iterations completed expected work:

```
┌─────────────────────────────────────────────────────────┐
│                   Supervisor Loop                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   1. Run main Ralph iteration                          │
│      ↓                                                  │
│   2. Check completion via supervisor script            │
│      ↓                                                  │
│   3. If check fails → Run nudge iteration              │
│      (one-off with supervisor prompt appended)         │
│      ↓                                                  │
│   4. Continue main loop                                │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Example use case:** Ensure translations are updated after each feature.

### Setup

1. **Create supervisor check script** (`.agent/sessions/myapp/supervisor.sh`):
```bash
#!/bin/bash
# Check if translations were updated

LOG_FILE="$1"

# Parse what files were modified from the log
if ! grep -q "i18n/translations" "$LOG_FILE"; then
  echo "Missing: translations not updated"
  exit 1  # Needs nudge
fi

exit 0  # All good
```

2. **Create nudge prompt** (`.agent/sessions/myapp/supervisor-nudge.md`):
```markdown
# Supervisor Check: Translations Missing

The previous iteration completed but did not update translations.

Please:
1. Add translations to `i18n/translations/en.json` for any new UI text
2. Verify translations are complete
3. Commit the translation updates
```

3. **Run with supervisor:**
```bash
export RALPH_SUPERVISOR_SCRIPT=.agent/sessions/myapp/supervisor.sh
export RALPH_SUPERVISOR_NUDGE=.agent/sessions/myapp/supervisor-nudge.md
ralph --session myapp claude
```

The supervisor script examines the log after each successful iteration. If it returns non-zero, Ralph runs one additional iteration with the nudge prompt to fix the issue.

## Context Window Awareness (The Smart Zone)

Ralph's effectiveness depends on efficient context usage. Understanding token limits helps you stay in the "smart zone."

### Token Budget

- **Total context:** ~200k tokens
- **Model overhead:** ~16k tokens
- **Harness overhead:** ~16k tokens
- **Usable context:** ~176k tokens (~136KB text, or 1-2 movie scripts)

### Staying in the Smart Zone

As the context window fills, model performance degrades. Signs you're in the "dumb zone":
- Model forgets earlier instructions
- Test fixing becomes scrambling/flailing
- Repeated attempts at the same fix
- Forgetting what task it was working on

**Mitigations:**
- **Keep each task small** - One feature = one iteration (Ralph handles this by design)
- **Minimize test output** - Only show failing tests, not full passing logs
- **Keep prompts concise** - Session `prompt.md` should be <100 lines
- **Use deliberate malicking** - Explicitly mention file paths to anchor context

### Test Output Optimization

Most test runners output too many tokens. Configure yours to only show failures:

```bash
# Example: wrapper script that filters test output
# .agent/test-wrapper.sh
#!/bin/bash
pnpm test --bail 2>&1 | grep -A10 "FAIL\|Error\|✗" || echo "All tests passed"
```

Then in your session `prompt.md`:
```markdown
# Build Commands
- Tests: `./.agent/test-wrapper.sh` (only shows failures)
```

**Token savings:** A full test suite with 200 passing tests can output 50k+ tokens. Filtered output: <5k tokens.

### Deliberate Malicking

"Malicking" = deliberately allocating context. The first ~5k tokens of each iteration should anchor critical context:

```markdown
# Context Anchors (read these first)
- `spec.md` - all tasks and acceptance criteria
- `specs/api-contract.md` - API requirements
- `src/services/auth.ts` - existing implementation
```

**Why this works:** Mentioning file paths by name triggers the model to read them at the start of iteration, ensuring they stay in the "smart zone" rather than being compressed or forgotten.

## Human on the Loop (The Fireplace Pattern)

Ralph works best with observation-driven tuning rather than constant intervention:

### The Pattern

1. **Watch like a fireplace** - Let iterations run and observe patterns
2. **Notice behaviors** - What does it do repeatedly? What does it miss?
3. **Tune your specs** - If it keeps making the same mistake, the spec is wrong
4. **Never blame the model** - Garbage in = garbage out

### Common Patterns

| Observation | Likely Cause | Fix |
|-------------|--------------|-----|
| Forgets translations every time | Not in acceptance criteria | Add to task acceptance: `- [ ] Translations updated` |
| Verbose test output causes confusion | Default test runner | Add filtered test wrapper script |
| Repeats same fix attempt | Ambiguous spec | Make spec more specific and testable |
| Skips certain file types | Not mentioned in context | Add to context anchors in prompt.md |
| Works on multiple tasks per iteration | Unclear instructions | Emphasize "ONE task" in session prompt |

### Iteration vs. Supervision

- **Human IN the loop:** Model asks permission for each action (slow, interrupts flow)
- **Human ON the loop:** Model runs autonomously, human observes and tunes (Ralph's design)

**You are the orchestrator.** Ralph is the inner loop. You tune:
- Task granularity (how big each task is)
- Acceptance criteria (what "done" means)
- Context anchors (what files to read)
- Supervisor checks (what to verify)

### Discoveries Through Observation

Some patterns you might discover:
- Opus doesn't have context window anxiety (unlike earlier models)
- Opus can be forgetful about certain categories of work
- Test runner output bloat is the #1 cause of context issues
- One bad spec line = 10,000 lines of wrong code

**The fireplace mindset:** Treat Ralph like a live stream you check in on. Watch for patterns, notice when behavior changes, ask yourself why—then tune the specs and prompts accordingly.

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
