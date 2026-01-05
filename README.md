# ralph

Minimal loop runner for Claude CLI or Codex CLI.

## Quick start

Install the global `ralph` wrapper:

```bash
./install.sh
```

Then use it from any repo.

1) Write your spec in `prompt.md` (or use a session).
2) Run the loop:

```bash
ralph claude
# or
ralph codex
```

Stop with Ctrl+C, or create `.agent/STOP`.

## Sessions (recommended)

Create a session scaffold:

```bash
ralph init feature-x
```

Edit the session PRD and prompt:

- `.agent/sessions/feature-x/prd.json`
- `.agent/sessions/feature-x/progress.txt`
- `.agent/sessions/feature-x/prompt.md`

The base Ralph instructions now ship in `ralph.sh`. Session prompts only need
to include paths/scope notes.

Run a session:

```bash
ralph --session feature-x codex
# or
ralph --session feature-x claude
```

List sessions:

```bash
ralph list
```

## Notes

- Logs are written to `.agent/logs/`.
- The loop calls itself each iteration via `./ralph.sh --once <cli>`.
- Edit `ralph.sh` if you want to tweak flags or add safety checks.

## Prompts

- Base prompt is built into `ralph.sh` (used if no prompt file is provided).
- Set `RALPH_PROMPT_FILE=/path/to/custom.md` to fully override the base prompt.
- Set `RALPH_PROMPT_APPEND_FILE=/path/to/extra.md` to append custom instructions.

## Completion + limits

- Ralph will stop early if the model outputs `<promise>COMPLETE</promise>`.
- Set `RALPH_MAX_ITERATIONS` or pass `--iterations <n>` to cap loop runs.

## Notifications

- Set `RALPH_NOTIFY=1` to trigger a macOS notification on completion.
- Or set `RALPH_NOTIFY_CMD` to run a custom command on completion.

## Ralph Planner Skill

Packaged skill file (for installation on other machines):

- `skills/ralph-planner.skill`

This skill helps plan and shape Ralph sessions (PRD + prompt) and never runs Ralph.

## Updating

### Update the `ralph` command

After pulling changes to this repo, re-run:

```bash
./install.sh
```

This re-copies `ralph.sh` into `~/.local/share/ralph/ralph.sh`.

### Update the skill

The distributable skill lives at:

- `skills/ralph-planner.skill`

After changes to the skill, re-package and copy the `.skill` file to other machines.

## Requirements

- `claude` CLI installed and authenticated (for `claude` mode).
- `codex` CLI installed and authenticated (for `codex` mode).

### CLI references

- Claude CLI: https://docs.anthropic.com/en/docs/claude-code/cli-reference
- Codex CLI: https://developers.openai.com/codex/cli
