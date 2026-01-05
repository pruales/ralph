#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

AGENT_DIR="$ROOT_DIR/.agent"
PROMPT_FILE="${RALPH_PROMPT_FILE:-$ROOT_DIR/prompt.md}"
LOG_DIR="$AGENT_DIR/logs"
STOP_FILE="$AGENT_DIR/STOP"
SLEEP_SECONDS="${RALPH_SLEEP_SECONDS:-10}"

usage() {
  cat <<'USAGE'
Usage:
  ./ralph.sh <claude|codex>      Run forever (calls itself each iteration)
  ./ralph.sh --once <claude|codex> Run a single iteration

Environment:
  RALPH_PROMPT_FILE   Override prompt file path (default: ./prompt.md)
  RALPH_SLEEP_SECONDS Sleep between iterations (default: 10)
USAGE
}

MODE="loop"
if [[ "${1:-}" == "--once" ]]; then
  MODE="once"
  shift
fi

CLI="${1:-}"
if [[ -z "$CLI" ]]; then
  usage
  exit 1
fi

shift || true

mkdir -p "$LOG_DIR"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "prompt.md not found at: $PROMPT_FILE"
  exit 1
fi

run_claude() {
  local ts log
  ts="$(date +%Y%m%d_%H%M%S)"
  log="$LOG_DIR/claude_${ts}.log"

  # Uses prompt.md as the full prompt text.
  claude -p --output-format=json "$(cat "$PROMPT_FILE")" | tee -a "$log"
}

run_codex() {
  local ts log
  ts="$(date +%Y%m%d_%H%M%S)"
  log="$LOG_DIR/codex_${ts}.log"

  # Uses prompt.md as the full prompt text (read from stdin).
  cat "$PROMPT_FILE" | codex exec - | tee -a "$log"
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
}

if [[ "$MODE" == "once" ]]; then
  run_once
  exit 0
fi

trap 'echo "\nStopping..."; exit 0' INT TERM

echo "Starting loop with: $CLI"

while :; do
  if [[ -f "$STOP_FILE" ]]; then
    echo "Stop file found at $STOP_FILE"
    break
  fi

  "$0" --once "$CLI" || echo "Iteration failed"

  if [[ -f "$STOP_FILE" ]]; then
    echo "Stop file found at $STOP_FILE"
    break
  fi

  echo "===SLEEP==="
  sleep "$SLEEP_SECONDS"
done
