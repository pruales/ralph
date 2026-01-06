#!/bin/bash
set -euo pipefail

VERSION="0.2.1"

resolve_root_dir() {
  if [[ -n "${RALPH_ROOT_DIR:-}" ]]; then
    echo "$RALPH_ROOT_DIR"
    return
  fi
  if git -C "${PWD}" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "${PWD}" rev-parse --show-toplevel
    return
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

ROOT_DIR="$(resolve_root_dir)"
if [[ ! -d "$ROOT_DIR" ]]; then
  echo "Root directory not found: $ROOT_DIR"
  exit 1
fi
cd "$ROOT_DIR"

AGENT_DIR="$ROOT_DIR/.agent"
BASE_PROMPT_FILE="$ROOT_DIR/prompt.md"
PROMISE_PATTERN="${RALPH_PROMISE_PATTERN:-<promise>COMPLETE</promise>}"
SLEEP_SECONDS="${RALPH_SLEEP_SECONDS:-10}"
MAX_ITERATIONS="${RALPH_MAX_ITERATIONS:-}"

usage() {
  cat <<'USAGE'
Usage:
  ./ralph.sh <claude|codex>             Run forever (calls itself each iteration)
  ./ralph.sh --once <claude|codex>      Run a single iteration
  ./ralph.sh --session <name> <claude|codex> Run against a named session
  ./ralph.sh --init-session <name>      Create a new session scaffold
  ./ralph.sh init <name>                Create a new session scaffold
  ./ralph.sh list                       List existing sessions
  ./ralph.sh clean [--session <name>]   Clean up logs (remove empty, compress old)

Environment:
  RALPH_ROOT_DIR          Override repo root directory
  RALPH_PROMPT_FILE        Override prompt file path (default: ./prompt.md)
  RALPH_PROMPT_APPEND_FILE Append custom instructions to the base/session prompt
  RALPH_SPEC_FILE         Override spec.md path injected into the prompt
  RALPH_PROGRESS_FILE     Override progress log path injected into the prompt
  RALPH_SESSION            Default session name (same as --session)
  RALPH_SLEEP_SECONDS      Sleep between iterations (default: 10)
  RALPH_MAX_ITERATIONS    Max iterations before stopping (loop mode)
  RALPH_PROMISE_PATTERN   Completion marker to stop on (default: <promise>COMPLETE</promise>)
  RALPH_SUPERVISOR_SCRIPT  Path to executable supervisor check script
  RALPH_SUPERVISOR_NUDGE   Path to nudge prompt when supervisor check fails
  RALPH_NOTIFY            If set to 1, send macOS notification on completion
  RALPH_NOTIFY_CMD        Optional shell command to run on completion
  RALPH_CLAUDE_OUTPUT_FORMAT Claude output format (default: stream-json)
  RALPH_CLAUDE_PARTIAL     If set to 1, include partial messages in stream-json
  RALPH_CLAUDE_PRETTY      If set to 1, print only the final result when using stream-json (requires jq)
  RALPH_CLAUDE_PERMISSION_MODE Claude permission mode (default: bypassPermissions)
  RALPH_CODEX_YOLO        Bypass approvals and sandbox (default: 1, set to 0 to disable)
  RALPH_CODEX_APPROVAL    Codex approval mode when YOLO=0 (default: never)
  RALPH_CODEX_SANDBOX     Codex sandbox mode when YOLO=0 (default: workspace-write)
  RALPH_CODEX_PRETTY      If set to 1 (default), pretty-print Codex output (requires jq)
USAGE
}

MODE="loop"
SESSION="${RALPH_SESSION:-}"
INIT_SESSION=""
ITERATIONS_OVERRIDE=""
PRD_OVERRIDE=""
PROGRESS_OVERRIDE=""

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)
      MODE="once"
      shift
      ;;
    --iterations|-n)
      if [[ $# -lt 2 ]]; then
        echo "--iterations requires a number"
        exit 1
      fi
      ITERATIONS_OVERRIDE="$2"
      shift 2
      ;;
    --prd)
      if [[ $# -lt 2 ]]; then
        echo "--prd requires a path"
        exit 1
      fi
      PRD_OVERRIDE="$2"
      shift 2
      ;;
    --progress)
      if [[ $# -lt 2 ]]; then
        echo "--progress requires a path"
        exit 1
      fi
      PROGRESS_OVERRIDE="$2"
      shift 2
      ;;
    --session)
      if [[ $# -lt 2 ]]; then
        echo "--session requires a name"
        exit 1
      fi
      SESSION="$2"
      shift 2
      ;;
    --init-session)
      if [[ $# -lt 2 ]]; then
        echo "--init-session requires a name"
        exit 1
      fi
      INIT_SESSION="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --version|-v)
      echo "ralph $VERSION"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]}"

validate_session_name() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Session name is required."
    exit 1
  fi
  if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Invalid session name: $name (use letters, numbers, dot, underscore, dash)"
    exit 1
  fi
}

base_prompt() {
  cat <<'BASE'
# Context (read these first - these files contain source of truth)
@SPEC_FILE@
@PROGRESS_FILE@

# Your Task
1. Pick the SINGLE highest-priority incomplete task from the spec (⬜ status).
2. Implement ONLY that task - stay focused on one feature.
3. Run tests - only output FAILING test output (suppress passing tests to save tokens).
4. Update spec.md to mark the task complete:
   - Change `### ⬜ Task:` to `### ✅ Task:`
   - Change `**Status:** incomplete` to `**Status:** complete`
   - Check all acceptance boxes: `- [ ]` → `- [x]`
5. Append a brief note to progress.txt for the next iteration.
6. Git commit with a clear, descriptive message.

# Critical Rules
- ONE task per iteration - stop after completing one task
- Keep test output minimal - only show failures, not full passing logs
- If ALL tasks in spec are ✅ complete, output <promise>COMPLETE</promise>
- Stay in the smart zone: don't overload context with verbose logs or excessive output
BASE
}

build_prompt_file() {
  local tmp
  tmp="$(mktemp "$AGENT_DIR/prompt.XXXXXX")"
  TEMP_PROMPT_FILE="$tmp"

  if [[ -n "${RALPH_PROMPT_FILE:-}" ]]; then
    cat "$RALPH_PROMPT_FILE" > "$tmp"
  elif [[ -f "$BASE_PROMPT_FILE" ]]; then
    cat "$BASE_PROMPT_FILE" > "$tmp"
  else
    base_prompt > "$tmp"
  fi

  if [[ -n "$SESSION" ]]; then
    local session_prompt="$SESSION_DIR/prompt.md"
    if [[ -f "$session_prompt" ]]; then
      printf "\n\n# Session Instructions\n" >> "$tmp"
      cat "$session_prompt" >> "$tmp"
    fi
  fi

  if [[ -n "${RALPH_PROMPT_APPEND_FILE:-}" ]]; then
    printf "\n\n# Additional Instructions\n" >> "$tmp"
    cat "$RALPH_PROMPT_APPEND_FILE" >> "$tmp"
  fi

  local spec_path progress_path spec_esc progress_esc
  if [[ -n "$PRD_OVERRIDE" ]]; then
    spec_path="$PRD_OVERRIDE"
  elif [[ -n "${RALPH_SPEC_FILE:-}" ]]; then
    spec_path="$RALPH_SPEC_FILE"
  elif [[ -n "$SESSION" ]]; then
    spec_path="$SESSION_DIR/spec.md"
  else
    spec_path="$ROOT_DIR/spec.md"
  fi

  if [[ -n "$PROGRESS_OVERRIDE" ]]; then
    progress_path="$PROGRESS_OVERRIDE"
  elif [[ -n "${RALPH_PROGRESS_FILE:-}" ]]; then
    progress_path="$RALPH_PROGRESS_FILE"
  elif [[ -n "$SESSION" ]]; then
    progress_path="$SESSION_DIR/progress.txt"
  else
    progress_path="$ROOT_DIR/progress.txt"
  fi

  spec_esc="$(printf '%s' "$spec_path" | sed -e 's/[&|\\/]/\\&/g')"
  progress_esc="$(printf '%s' "$progress_path" | sed -e 's/[&|\\/]/\\&/g')"
  # Prefix paths with @ for Claude Code / Codex file reference syntax
  sed -e "s|@SPEC_FILE@|@$spec_esc|g" -e "s|@PROGRESS_FILE@|@$progress_esc|g" "$tmp" > "${tmp}.new"
  mv "${tmp}.new" "$tmp"

  PROMPT_FILE="$tmp"
}

init_session() {
  local name="$1"
  validate_session_name "$name"
  local dir="$AGENT_DIR/sessions/$name"
  if [[ -e "$dir" ]]; then
    echo "Session already exists: $dir"
    exit 1
  fi

  mkdir -p "$dir"
  mkdir -p "$dir/logs"

  cat > "$dir/spec.md" <<'SPEC'
# Session: Example

## Overview
Describe what you're building and why. This section provides high-level context.

## Context & Requirements
Document key details here:
- Architecture decisions
- API contracts
- Design constraints
- External dependencies
- Links to relevant specs or docs

## Tasks

### ⬜ Task: example-feature
**Priority:** high
**Status:** incomplete

Brief description of what needs to be implemented.

**Acceptance:**
- [ ] Specific, testable criterion 1
- [ ] Specific, testable criterion 2
- [ ] Specific, testable criterion 3

**Notes:**
Any implementation hints or context specific to this task.

---

SPEC

  cat > "$dir/progress.txt" <<'TXT'
Session created. Append notes here after each run.
TXT

  cat > "$dir/prompt.md" <<'PROMPT'
# Context Anchors (read these first)
These files contain the source of truth for this work:
- `spec.md` - session spec with tasks and acceptance criteria

# Build Commands
- Typecheck: `pnpm typecheck` (or adjust for your project)
- Tests: `pnpm test` (only show failures to save tokens)

# Scope
- Focus areas: describe which directories/files to modify
- Do NOT touch: describe what to avoid (migrations, CI config, etc.)

# Conventions
- Coding style or patterns to follow
- Naming conventions
- Any project-specific guidelines
PROMPT

  echo "Session created at: $dir"
}

list_sessions() {
  local dir="$AGENT_DIR/sessions"
  if [[ ! -d "$dir" ]]; then
    echo "No sessions found."
    return 0
  fi

  local found=0
  for path in "$dir"/*; do
    if [[ -d "$path" ]]; then
      found=1
      echo "$(basename "$path")"
    fi
  done

  if [[ "$found" -eq 0 ]]; then
    echo "No sessions found."
  fi
}

# Log management functions

prompt_hash() {
  # Compute hash of prompt file for deduplication
  local file="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$file" | cut -d' ' -f1
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$file"
  else
    # Fallback: use file size + first/last lines
    wc -c < "$file" | tr -d ' '
  fi
}

prompt_changed() {
  # Check if prompt differs from last run
  local prompt_file="$1"
  local log_dir="$2"
  local hash_file="$log_dir/.last_prompt_hash"

  local current_hash
  current_hash="$(prompt_hash "$prompt_file")"

  if [[ -f "$hash_file" ]]; then
    local last_hash
    last_hash="$(cat "$hash_file")"
    if [[ "$current_hash" == "$last_hash" ]]; then
      return 1  # Not changed
    fi
  fi

  # Save current hash
  echo "$current_hash" > "$hash_file"
  return 0  # Changed
}

finalize_run_log() {
  # Combine prompt, transcript, and summary into single markdown file
  local cli="$1"
  local ts="$2"
  local log_dir="$3"
  local prompt_file="$4"
  local transcript_file="$5"
  local summary_file="${6:-}"

  local combined="$log_dir/${cli}_${ts}.md"
  local prompt_changed_flag="$7"

  {
    echo "# Ralph Run: $cli"
    echo ""
    echo "**Timestamp:** $(date -r "${transcript_file}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Include prompt only if changed
    if [[ "$prompt_changed_flag" == "1" ]]; then
      echo "## Prompt"
      echo ""
      echo '```markdown'
      cat "$prompt_file"
      echo '```'
      echo ""
    else
      echo "## Prompt"
      echo ""
      echo "*Unchanged from previous run*"
      echo ""
    fi

    echo "## Transcript"
    echo ""
    if [[ -s "$transcript_file" ]]; then
      echo '```json'
      cat "$transcript_file"
      echo '```'
    else
      echo "*No output captured*"
    fi
    echo ""

    # Include summary if available
    if [[ -n "$summary_file" && -f "$summary_file" && -s "$summary_file" ]]; then
      echo "## Summary"
      echo ""
      cat "$summary_file"
      echo ""
    fi
  } > "$combined"

  # Remove individual files
  rm -f "$transcript_file"
  [[ -n "$summary_file" && -f "$summary_file" ]] && rm -f "$summary_file"

  # Compress immediately if RALPH_COMPRESS_LOGS=1
  if [[ "${RALPH_COMPRESS_LOGS:-0}" == "1" ]]; then
    gzip "$combined"
    echo "Log saved to: ${combined}.gz"
  else
    echo "Log saved to: $combined"
  fi
}

compress_old_logs() {
  # Compress logs older than 1 day
  local log_dir="$1"
  local count=0

  while IFS= read -r -d '' file; do
    gzip "$file" 2>/dev/null && ((count++)) || true
  done < <(find "$log_dir" -name "*.md" -type f -mtime +1 -print0 2>/dev/null)

  if [[ "$count" -gt 0 ]]; then
    echo "Compressed $count old log(s)"
  fi
}

clean_logs() {
  # Clean up logs: remove empty files, compress old logs
  local log_dir="$1"
  local empty_count=0
  local compress_count=0

  if [[ ! -d "$log_dir" ]]; then
    echo "Log directory not found: $log_dir"
    return 1
  fi

  # Remove empty files
  while IFS= read -r -d '' file; do
    rm -f "$file" && ((empty_count++)) || true
  done < <(find "$log_dir" -type f -empty -print0 2>/dev/null)

  # Compress uncompressed logs older than 1 day
  while IFS= read -r -d '' file; do
    gzip "$file" 2>/dev/null && ((compress_count++)) || true
  done < <(find "$log_dir" -name "*.md" -type f -mtime +1 -print0 2>/dev/null)

  # Also compress old .log files (legacy format)
  while IFS= read -r -d '' file; do
    gzip "$file" 2>/dev/null && ((compress_count++)) || true
  done < <(find "$log_dir" -name "*.log" -type f -mtime +1 -print0 2>/dev/null)

  echo "Cleaned: removed $empty_count empty file(s), compressed $compress_count old log(s)"
}

if [[ -n "$INIT_SESSION" ]]; then
  init_session "$INIT_SESSION"
  exit 0
fi

CLI="${1:-}"
if [[ "$CLI" == "init" ]]; then
  if [[ $# -lt 2 ]]; then
    echo "init requires a session name"
    exit 1
  fi
  init_session "$2"
  exit 0
fi

if [[ "$CLI" == "list" ]]; then
  list_sessions
  exit 0
fi

if [[ "$CLI" == "clean" ]]; then
  # Determine which log directory to clean
  clean_dir="$AGENT_DIR/logs"
  if [[ -n "$SESSION" ]]; then
    clean_dir="$AGENT_DIR/sessions/$SESSION/logs"
  fi
  clean_logs "$clean_dir"
  exit 0
fi

if [[ -z "$CLI" ]]; then
  usage
  exit 1
fi

shift || true

PROMPT_FILE="${RALPH_PROMPT_FILE:-$BASE_PROMPT_FILE}"
LOG_DIR="$AGENT_DIR/logs"
STOP_FILE="$AGENT_DIR/STOP"

if [[ -n "$SESSION" ]]; then
  validate_session_name "$SESSION"
  SESSION_DIR="$AGENT_DIR/sessions/$SESSION"
  if [[ -z "${RALPH_PROMPT_FILE:-}" ]]; then
    PROMPT_FILE="$SESSION_DIR/prompt.md"
  fi
  LOG_DIR="$SESSION_DIR/logs"
  STOP_FILE="$SESSION_DIR/STOP"
fi

mkdir -p "$LOG_DIR"

build_prompt_file
trap '[[ -n "${TEMP_PROMPT_FILE:-}" ]] && rm -f "$TEMP_PROMPT_FILE"' EXIT

run_claude() {
  local ts transcript_file
  ts="$(date +%Y%m%d_%H%M%S)"
  transcript_file="$LOG_DIR/.claude_${ts}_transcript.json"
  LAST_LOG="$LOG_DIR/claude_${ts}.md"

  # Check if prompt changed
  local prompt_changed_flag="0"
  if prompt_changed "$PROMPT_FILE" "$LOG_DIR"; then
    prompt_changed_flag="1"
  fi

  # Uses prompt.md as the full prompt text.
  local output_format
  output_format="${RALPH_CLAUDE_OUTPUT_FORMAT:-stream-json}"
  local permission_mode
  permission_mode="${RALPH_CLAUDE_PERMISSION_MODE:-bypassPermissions}"

  echo "Starting Claude run..."
  local start_ts end_ts duration
  start_ts="$(date +%s)"
  local verbose_flag
  verbose_flag=""
  if [[ "$output_format" == "stream-json" ]]; then
    verbose_flag="--verbose"
  fi

  local pretty
  pretty="${RALPH_CLAUDE_PRETTY:-1}"

  if [[ "$output_format" == "stream-json" && "$pretty" == "1" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
      echo "jq not found; streaming JSON will be printed. Install jq or set RALPH_CLAUDE_OUTPUT_FORMAT=text."
      pretty="0"
    fi
  fi

  if [[ "$output_format" == "stream-json" && "${RALPH_CLAUDE_PARTIAL:-}" == "1" ]]; then
    if [[ "$pretty" == "1" ]]; then
      claude -p $verbose_flag --permission-mode "$permission_mode" --output-format "$output_format" --include-partial-messages "$(cat "$PROMPT_FILE")" | tee "$transcript_file" | jq -r 'select(.type=="result") | .result'
    else
      claude -p $verbose_flag --permission-mode "$permission_mode" --output-format "$output_format" --include-partial-messages "$(cat "$PROMPT_FILE")" | tee "$transcript_file"
    fi
  else
    if [[ "$pretty" == "1" ]]; then
      claude -p $verbose_flag --permission-mode "$permission_mode" --output-format "$output_format" "$(cat "$PROMPT_FILE")" | tee "$transcript_file" | jq -r 'select(.type=="result") | .result'
    else
      claude -p $verbose_flag --permission-mode "$permission_mode" --output-format "$output_format" "$(cat "$PROMPT_FILE")" | tee "$transcript_file"
    fi
  fi
  end_ts="$(date +%s)"
  duration=$((end_ts - start_ts))
  echo "Finished Claude run in ${duration}s."

  # Combine into single file
  finalize_run_log "claude" "$ts" "$LOG_DIR" "$PROMPT_FILE" "$transcript_file" "" "$prompt_changed_flag"

  # Compress old logs
  compress_old_logs "$LOG_DIR"
}

run_codex() {
  local ts transcript_file summary_file
  ts="$(date +%Y%m%d_%H%M%S)"
  transcript_file="$LOG_DIR/.codex_${ts}_transcript.jsonl"
  summary_file="$LOG_DIR/.codex_${ts}_summary.md"
  LAST_LOG="$LOG_DIR/codex_${ts}.md"

  # Check if prompt changed
  local prompt_changed_flag="0"
  if prompt_changed "$PROMPT_FILE" "$LOG_DIR"; then
    prompt_changed_flag="1"
  fi

  # Uses prompt.md as the full prompt text (read from stdin).
  # Default to yolo mode unless RALPH_CODEX_YOLO=0
  local yolo
  yolo="${RALPH_CODEX_YOLO:-1}"

  echo "Starting Codex run..."
  local start_ts end_ts duration
  start_ts="$(date +%s)"

  local pretty
  pretty="${RALPH_CODEX_PRETTY:-1}"
  if [[ "$pretty" == "1" ]] && ! command -v jq >/dev/null 2>&1; then
    echo "jq not found; streaming JSON will be printed. Install jq or set RALPH_CODEX_PRETTY=0."
    pretty="0"
  fi

  local jq_filter='select(.type == "item.completed") | .item |
    if .type == "reasoning" then "💭 " + .text
    elif .type == "command_execution" then "$ " + .command + "\n" + .aggregated_output
    elif .type == "message" then .content
    else empty end'

  if [[ "$yolo" == "1" ]]; then
    if [[ "$pretty" == "1" ]]; then
      cat "$PROMPT_FILE" | codex exec --yolo --json -o "$summary_file" - | tee "$transcript_file" | jq -r "$jq_filter"
    else
      cat "$PROMPT_FILE" | codex exec --yolo --json -o "$summary_file" - | tee "$transcript_file"
    fi
  else
    local approval sandbox
    approval="${RALPH_CODEX_APPROVAL:-never}"
    sandbox="${RALPH_CODEX_SANDBOX:-workspace-write}"
    if [[ "$pretty" == "1" ]]; then
      cat "$PROMPT_FILE" | codex -a "$approval" exec --sandbox "$sandbox" --json -o "$summary_file" - | tee "$transcript_file" | jq -r "$jq_filter"
    else
      cat "$PROMPT_FILE" | codex -a "$approval" exec --sandbox "$sandbox" --json -o "$summary_file" - | tee "$transcript_file"
    fi
  fi

  # Show summary at end if available
  if [[ -f "$summary_file" && -s "$summary_file" ]]; then
    echo ""
    echo "=== Summary ==="
    cat "$summary_file"
  fi
  end_ts="$(date +%s)"
  duration=$((end_ts - start_ts))
  echo "Finished Codex run in ${duration}s."

  # Combine into single file
  finalize_run_log "codex" "$ts" "$LOG_DIR" "$PROMPT_FILE" "$transcript_file" "$summary_file" "$prompt_changed_flag"

  # Compress old logs
  compress_old_logs "$LOG_DIR"
}

run_supervisor() {
  # Optional supervisor check after each iteration
  # Script should examine the log and return:
  #   0 = all good
  #   1 = needs nudge (run one-off iteration with supervisor prompt)
  local script="${RALPH_SUPERVISOR_SCRIPT:-}"
  if [[ -z "$script" || ! -x "$script" ]]; then
    return 0
  fi
  
  echo "Running supervisor check..."
  if ! "$script" "$LAST_LOG"; then
    echo "Supervisor check failed - running nudge iteration"
    local nudge_prompt="${RALPH_SUPERVISOR_NUDGE:-}"
    if [[ -n "$nudge_prompt" && -f "$nudge_prompt" ]]; then
      # Run one-off iteration with nudge prompt appended
      local old_append="${RALPH_PROMPT_APPEND_FILE:-}"
      export RALPH_PROMPT_APPEND_FILE="$nudge_prompt"
      "$0" --once "$CLI"
      export RALPH_PROMPT_APPEND_FILE="$old_append"
    else
      echo "Warning: RALPH_SUPERVISOR_NUDGE not set or file not found"
    fi
  fi
}

notify_complete() {
  local title message
  title="Ralph"
  message="PRD complete"
  if [[ -n "$SESSION" ]]; then
    message="PRD complete (session: $SESSION)"
  fi
  if [[ "${RALPH_NOTIFY:-}" == "1" ]]; then
    osascript -e "display notification \"${message}\" with title \"${title}\""
  fi
  if [[ -n "${RALPH_NOTIFY_CMD:-}" ]]; then
    RALPH_NOTIFY_TITLE="$title" RALPH_NOTIFY_MESSAGE="$message" bash -lc "$RALPH_NOTIFY_CMD"
  fi
}

check_promise_complete() {
  local log="$1"
  if [[ -z "$log" || ! -f "$log" ]]; then
    return 1
  fi
  # Only search after ## Transcript to avoid matching prompt instructions
  if sed -n '/^## Transcript/,$p' "$log" | grep -qF "$PROMISE_PATTERN"; then
    return 0
  fi
  return 1
}

run_once() {
  case "$CLI" in
    claude)
      run_claude
      ;;
    codex)
      run_codex
      ;;
    *)
      echo "Unknown CLI: $CLI"
      usage
      exit 1
      ;;
  esac

  if check_promise_complete "$LAST_LOG"; then
    echo "PRD complete, exiting."
    notify_complete
    return 2
  fi
}

if [[ "$MODE" == "once" ]]; then
  run_once
  exit 0
fi

trap 'echo "\nStopping..."; exit 0' INT TERM

echo "Starting loop with: $CLI"
iteration=0
if [[ -n "$ITERATIONS_OVERRIDE" ]]; then
  MAX_ITERATIONS="$ITERATIONS_OVERRIDE"
fi

while :; do
  iteration=$((iteration + 1))
  echo "Iteration $iteration"

  if [[ -n "$MAX_ITERATIONS" && "$iteration" -gt "$MAX_ITERATIONS" ]]; then
    echo "Reached max iterations ($MAX_ITERATIONS)."
    break
  fi

  if [[ -f "$STOP_FILE" ]]; then
    echo "Stop file found at $STOP_FILE"
    break
  fi

  if [[ -n "$SESSION" ]]; then
    if "$0" --once --session "$SESSION" "$CLI"; then
      status=0
    else
      status=$?
    fi
  else
    if "$0" --once "$CLI"; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -eq 2 ]]; then
    break
  elif [[ "$status" -ne 0 ]]; then
    echo "Iteration failed"
  else
    # Run supervisor check only on successful iterations
    run_supervisor
  fi

  if [[ -f "$STOP_FILE" ]]; then
    echo "Stop file found at $STOP_FILE"
    break
  fi

  echo "===SLEEP==="
  sleep "$SLEEP_SECONDS"
done
