# CLAUDE.md

## Project Overview

Ralph is a minimal loop runner for Claude Code or Codex CLI. It executes an agentic loop that works through a spec (spec.md) one task at a time, committing progress as it goes. Each iteration is a fresh context window.

## Key Files

```
ralph.sh              # Core implementation (single bash script)
CHANGELOG.md          # Version history (must match VERSION in ralph.sh)
hooks/pre-commit      # Enforces version sync
skills/ralph-planner/ # Claude Code skill for planning sessions
examples/             # Supervisor pattern examples
```

## Versioning System

**Manual versioning with pre-commit enforcement.**

- Version lives in `ralph.sh` line 4: `VERSION="X.Y.Z"`
- CHANGELOG.md header: `## Version X.Y.Z (YYYY-MM-DD)`
- Pre-commit hook blocks commits if versions don't match

### Bumping Version

1. Update `VERSION` in `ralph.sh` line 4
2. Add entry to `CHANGELOG.md` with matching version and today's date
3. Commit — hook validates match

```bash
# Hook installation (already done, but for reference)
ln -sf ../../hooks/pre-commit .git/hooks/pre-commit
```

### Semver Guidelines

- **Patch (0.0.X):** Bug fixes, minor tweaks
- **Minor (0.X.0):** New features, backward-compatible
- **Major (X.0.0):** Breaking changes (env var renames, file format changes)

## Development Workflow

### Testing Changes

```bash
# Run script directly
./ralph.sh --help
./ralph.sh --version

# Test pre-commit hook
./hooks/pre-commit

# Test with a session
./ralph.sh init test-session
./ralph.sh --session test-session --once claude
```

### Making Changes

1. Edit `ralph.sh`
2. If adding features/fixes, bump version in both files
3. Run `./hooks/pre-commit` to verify
4. Commit

## CHANGELOG Format

```markdown
## Version X.Y.Z (YYYY-MM-DD)

### Breaking Changes
- Description of breaking change

### New Features
- Description of new feature

### Bug Fixes
- Description of fix
```

## Environment Variables

Key variables to know when developing:

| Variable | Purpose |
|----------|---------|
| `RALPH_CLAUDE_PRETTY` | Pretty-print Claude JSON output (default: 1) |
| `RALPH_CODEX_PRETTY` | Pretty-print Codex JSON output (default: 1) |
| `RALPH_COMPRESS_LOGS` | Gzip logs immediately (default: 0) |

## Code Style

- Bash with `set -euo pipefail`
- Functions use `local` for variables
- Heredocs for multi-line strings
- Use `${VAR:-default}` for optional env vars
- Keep it simple — this is intentionally a single bash script

## Session Structure

When working on session-related code, understand this structure:

```
.agent/sessions/<name>/
├── spec.md        # Tasks in markdown (⬜/✅ status, checkboxes)
├── progress.txt   # Append-only log
├── prompt.md      # Session-specific instructions
└── logs/          # Run transcripts
```

## Task Format in spec.md

```markdown
### ⬜ Task: task-id
**Priority:** high|medium|low
**Status:** incomplete

Description here.

**Acceptance:**
- [ ] Criterion 1
- [ ] Criterion 2

---
```

When complete: change `⬜` to `✅`, `incomplete` to `complete`, check boxes `[x]`.

## Log Format

Logs combine prompt + transcript + summary into single `.md` files:
- Prompt only included if changed from previous run (deduplication)
- Old logs (>1 day) auto-compressed to `.gz`
- Use `ralph clean` to manually clean up
