#!/bin/bash
set -euo pipefail

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

Environment:
  RALPH_ROOT_DIR          Override repo root directory
  RALPH_PROMPT_FILE        Override prompt file path (default: ./prompt.md)
  RALPH_PROMPT_APPEND_FILE Append custom instructions to the base/session prompt
  RALPH_SESSION            Default session name (same as --session)
  RALPH_SLEEP_SECONDS      Sleep between iterations (default: 10)
  RALPH_MAX_ITERATIONS    Max iterations before stopping (loop mode)
  RALPH_PROMISE_PATTERN   Completion marker to stop on (default: <promise>COMPLETE</promise>)
  RALPH_NOTIFY            If set to 1, send macOS notification on completion
  RALPH_NOTIFY_CMD        Optional shell command to run on completion
  RALPH_CLAUDE_OUTPUT_FORMAT Claude output format (default: stream-json)
  RALPH_CLAUDE_PARTIAL     If set to 1, include partial messages in stream-json
  RALPH_CLAUDE_PRETTY      If set to 1, print only the final result when using stream-json (requires jq)
  RALPH_CLAUDE_PERMISSION_MODE Claude permission mode (default: bypassPermissions)
  RALPH_CODEX_APPROVAL    Codex approval mode (default: never)
  RALPH_CODEX_SANDBOX     Codex sandbox mode (default: workspace-write)
  RALPH_CODEX_YOLO        If set to 1, bypass approvals and sandbox
USAGE
}

MODE="loop"
SESSION="${RALPH_SESSION:-}"
INIT_SESSION=""
ITERATIONS_OVERRIDE=""

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
    *)
      break
      ;;
  esac
done

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
@plans/prd.json @progress.txt \
1. Find the highest-priority feature to work on and work only on that feature.
This should be the one YOU decide has the highest priority - not necessarily the first in the list. \
2. Check that the types check via pnpm typecheck and that the tests pass via pnpm test. \
3. Update the PRD with the work that was done. \
4. Append your progress to the progress.txt file.
Use this to leave a note for the next person working in the codebase. \
5. Make a git commit of that feature.
ONLY WORK ON A SINGLE FEATURE. \
If, while implementing the feature, you notice the PRD is complete, output <promise>COMPLETE</promise>.
BASE
}

build_prompt_file() {
  local tmp
  tmp="$(mktemp "$AGENT_DIR/prompt.XXXXXX.md")"
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
    if [[ -f "$session_prompt" && "${RALPH_PROMPT_FILE:-}" != "$session_prompt" ]]; then
      printf "\n\n# Session Instructions\n" >> "$tmp"
      cat "$session_prompt" >> "$tmp"
    fi
  fi

  if [[ -n "${RALPH_PROMPT_APPEND_FILE:-}" ]]; then
    printf "\n\n# Additional Instructions\n" >> "$tmp"
    cat "$RALPH_PROMPT_APPEND_FILE" >> "$tmp"
  fi

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

  cat > "$dir/prd.json" <<'JSON'
[
  {
    "id": "example-task",
    "title": "Example feature",
    "description": "Describe the feature or fix in one sentence.",
    "acceptance": [
      "List 2-5 acceptance checks",
      "Keep each check specific and testable"
    ],
    "priority": "high",
    "passes": false
  }
]
JSON

  cat > "$dir/progress.txt" <<'TXT'
Session created. Append notes here after each run.
TXT

  cat > "$dir/prompt.md" <<EOF
Session context:
- PRD: $dir/prd.json
- Progress log: $dir/progress.txt

Scope notes (optional):
- Describe any special constraints for this session here.
EOF

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
  local ts log
  ts="$(date +%Y%m%d_%H%M%S)"
  log="$LOG_DIR/claude_${ts}.log"
  LAST_LOG="$log"

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
      claude -p $verbose_flag --permission-mode "$permission_mode" --output-format "$output_format" --include-partial-messages "$(cat "$PROMPT_FILE")" | tee -a "$log" | jq -r 'select(.type=="result") | .result'
    else
      claude -p $verbose_flag --permission-mode "$permission_mode" --output-format "$output_format" --include-partial-messages "$(cat "$PROMPT_FILE")" | tee -a "$log"
    fi
  else
    if [[ "$pretty" == "1" ]]; then
      claude -p $verbose_flag --permission-mode "$permission_mode" --output-format "$output_format" "$(cat "$PROMPT_FILE")" | tee -a "$log" | jq -r 'select(.type=="result") | .result'
    else
      claude -p $verbose_flag --permission-mode "$permission_mode" --output-format "$output_format" "$(cat "$PROMPT_FILE")" | tee -a "$log"
    fi
  fi
  end_ts="$(date +%s)"
  duration=$((end_ts - start_ts))
  echo "Finished Claude run in ${duration}s."
}

run_codex() {
  local ts log
  ts="$(date +%Y%m%d_%H%M%S)"
  log="$LOG_DIR/codex_${ts}.log"
  LAST_LOG="$log"

  # Uses prompt.md as the full prompt text (read from stdin).
  local approval sandbox
  approval="${RALPH_CODEX_APPROVAL:-never}"
  sandbox="${RALPH_CODEX_SANDBOX:-workspace-write}"

  echo "Starting Codex run..."
  local start_ts end_ts duration
  start_ts="$(date +%s)"
  if [[ "${RALPH_CODEX_YOLO:-}" == "1" ]]; then
    cat "$PROMPT_FILE" | codex exec --dangerously-bypass-approvals-and-sandbox - | tee -a "$log"
  else
    cat "$PROMPT_FILE" | codex exec --ask-for-approval "$approval" --sandbox "$sandbox" - | tee -a "$log"
  fi
  end_ts="$(date +%s)"
  duration=$((end_ts - start_ts))
  echo "Finished Codex run in ${duration}s."
}

notify_complete() {
  if [[ "${RALPH_NOTIFY:-}" == "1" ]]; then
    osascript -e 'display notification "PRD complete" with title "Ralph"'
  fi
  if [[ -n "${RALPH_NOTIFY_CMD:-}" ]]; then
    bash -lc "$RALPH_NOTIFY_CMD"
  fi
}

check_promise_complete() {
  local log="$1"
  if [[ -z "$log" || ! -f "$log" ]]; then
    return 1
  fi
  if grep -qF "$PROMISE_PATTERN" "$log"; then
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
  fi

  if [[ -f "$STOP_FILE" ]]; then
    echo "Stop file found at $STOP_FILE"
    break
  fi

  echo "===SLEEP==="
  sleep "$SLEEP_SECONDS"
done
