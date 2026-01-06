# Ralph Examples

This directory contains example configurations for advanced Ralph patterns.

## Supervisor Pattern

The supervisor pattern allows you to check each iteration's work and automatically run a "nudge" iteration if certain criteria aren't met.

### Files

- `supervisor-example.sh` - Example supervisor check script
- `supervisor-nudge-example.md` - Example nudge prompt for failed checks

### How It Works

1. **Supervisor script runs after each successful iteration**
   - Examines the log file from the completed iteration
   - Returns exit code 0 if all checks pass
   - Returns exit code 1 if nudge is needed
   
2. **If checks fail, nudge iteration runs**
   - Ralph runs one additional iteration
   - The nudge prompt is appended to the normal prompt
   - This gives the agent a chance to fix the oversight
   
3. **Main loop continues**
   - After the nudge (if needed), the main loop continues with the next task

### Usage Example

```bash
# Copy and customize the supervisor files for your session
cp examples/supervisor-example.sh .agent/sessions/myapp/supervisor.sh
cp examples/supervisor-nudge-example.md .agent/sessions/myapp/nudge.md

# Edit the supervisor script to check for your specific requirements
vim .agent/sessions/myapp/supervisor.sh

# Edit the nudge prompt to guide the agent
vim .agent/sessions/myapp/nudge.md

# Make the supervisor script executable
chmod +x .agent/sessions/myapp/supervisor.sh

# Run Ralph with supervisor
export RALPH_SUPERVISOR_SCRIPT=.agent/sessions/myapp/supervisor.sh
export RALPH_SUPERVISOR_NUDGE=.agent/sessions/myapp/nudge.md
ralph --session myapp claude
```

### Common Use Cases

| Use Case | Check For | Nudge Prompt |
|----------|-----------|--------------|
| **Translations** | UI files changed but no translation updates | Add missing translation keys |
| **Documentation** | New API endpoints but no API docs | Document the new endpoints |
| **Tests** | Code changes but test count didn't increase | Add tests for new functionality |
| **Type safety** | New functions but no type definitions | Add TypeScript types |
| **Migrations** | Database schema changes but no migration | Create migration file |

### Example Supervisor Checks

#### Check for Translations

```bash
#!/bin/bash
LOG_FILE="$1"

if grep -q "src/components\|src/pages" "$LOG_FILE"; then
  if ! grep -q "i18n/translations" "$LOG_FILE"; then
    echo "UI changed but translations not updated"
    exit 1
  fi
fi

exit 0
```

#### Check for Tests

```bash
#!/bin/bash
LOG_FILE="$1"

# Extract file changes from log (customize based on your log format)
if grep -q "src/.*\.ts" "$LOG_FILE"; then
  if ! grep -q "test.*\.ts\|spec.*\.ts" "$LOG_FILE"; then
    echo "Code changed but no tests added"
    exit 1
  fi
fi

exit 0
```

#### Check for Documentation

```bash
#!/bin/bash
LOG_FILE="$1"

if grep -q "src/api/.*\.ts" "$LOG_FILE"; then
  if ! grep -q "docs/api\|README" "$LOG_FILE"; then
    echo "API changed but docs not updated"
    exit 1
  fi
fi

exit 0
```

### Tips

1. **Keep checks simple** - Supervisor should run quickly (<1 second)
2. **Be specific in nudge prompts** - Tell the agent exactly what was missed
3. **Don't over-nudge** - Too many checks can slow down the loop
4. **Log your checks** - Echo messages so you can see what triggered the nudge
5. **Test your supervisor** - Run it manually on a log file first

### Advanced: Multiple Supervisors

You can chain multiple checks in one script:

```bash
#!/bin/bash
LOG_FILE="$1"
FAILED_CHECKS=()

# Check 1: Translations
if grep -q "src/components" "$LOG_FILE"; then
  if ! grep -q "i18n/translations" "$LOG_FILE"; then
    FAILED_CHECKS+=("translations")
  fi
fi

# Check 2: Tests
if grep -q "src/.*\.ts" "$LOG_FILE"; then
  if ! grep -q "test.*\.ts" "$LOG_FILE"; then
    FAILED_CHECKS+=("tests")
  fi
fi

# Report results
if [[ ${#FAILED_CHECKS[@]} -gt 0 ]]; then
  echo "Failed checks: ${FAILED_CHECKS[*]}"
  exit 1
fi

echo "All checks passed"
exit 0
```

Then create a comprehensive nudge prompt that addresses all potential issues.
