# ralph

Minimal loop runner for Claude CLI or Codex CLI.

## Quick start

1) Write your spec in `prompt.md`.
2) Run the loop:

```bash
./ralph.sh claude
# or
./ralph.sh codex
```

Stop with Ctrl+C, or create `.agent/STOP`.

## Notes

- Logs are written to `.agent/logs/`.
- The loop calls itself each iteration via `./ralph.sh --once <cli>`.
- Edit `ralph.sh` if you want to tweak flags or add safety checks.

## Requirements

- `claude` CLI installed and authenticated (for `claude` mode).
- `codex` CLI installed and authenticated (for `codex` mode).

### CLI references

- Claude CLI: https://docs.anthropic.com/en/docs/claude-code/cli-reference
- Codex CLI: https://developers.openai.com/codex/cli

