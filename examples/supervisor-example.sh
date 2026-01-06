#!/bin/bash
# Example supervisor script for Ralph
# This checks if certain work was completed in each iteration

LOG_FILE="$1"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Error: Log file not found: $LOG_FILE"
  exit 2
fi

# Example check: Ensure translations were updated if any UI files changed
if grep -q "src/components" "$LOG_FILE" || grep -q "src/pages" "$LOG_FILE"; then
  if ! grep -q "i18n/translations" "$LOG_FILE"; then
    echo "❌ UI files changed but translations not updated"
    exit 1  # Needs nudge
  fi
fi

# Example check: Ensure tests were run
if ! grep -q "pnpm test\|npm test\|yarn test" "$LOG_FILE"; then
  echo "⚠️  Warning: Tests may not have been run"
  # Could exit 1 here to force test runs, or just warn
fi

# All checks passed
echo "✅ Supervisor checks passed"
exit 0
