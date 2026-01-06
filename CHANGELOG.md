# Changelog

## Version 0.2.1 (2026-01-06)

### Bug Fixes

- **Fixed false-positive completion detection** - `check_promise_complete()` now only searches the Transcript section of logs, avoiding false matches when the prompt instructions contain `<promise>COMPLETE</promise>`

### Improvements

- **Clarified task completion instructions** - Base prompt now explicitly lists all three spec updates: header emoji (⬜→✅), status line, and acceptance checkboxes

## Version 0.2.0 (2026-01-05)

### Breaking Changes

- **Replaced `prd.json` with `spec.md`**
  - Sessions now use a single markdown file for specs and tasks
  - Task format uses checklist syntax (`- [ ]` / `- [x]`)
  - Status indicators use emoji (⬜ incomplete, ✅ complete)
  - More token-efficient and easier for AI to read/update
  - No backward compatibility with `prd.json` format

- **Environment variable renamed**
  - `RALPH_PRD_FILE` → `RALPH_SPEC_FILE`

### New Features

#### 1. Supervisor Loop Pattern
- Added `RALPH_SUPERVISOR_SCRIPT` and `RALPH_SUPERVISOR_NUDGE` environment variables
- Supervisor scripts can check iteration output and trigger corrective nudges
- Example supervisor scripts in `examples/` directory
- Useful for ensuring translations, tests, docs, etc. are updated

#### 2. Enhanced Base Prompt
- Explicit "Context Anchors" section for deliberate malicking
- Emphasis on token efficiency (minimal test output)
- Clearer one-task-per-iteration guidance
- Smart zone awareness built in

#### 3. Improved Session Structure
- `spec.md` combines requirements + tasks in one file
- Better context anchor examples in default `prompt.md`
- More explicit guidance on scope and conventions

#### 4. Documentation Improvements
- Added "Context Window Awareness" section explaining the smart zone
- Added "Human on the Loop" section (fireplace pattern)
- Added "Supervisor Loop Pattern" with examples
- Token budget guidance and test output optimization tips
- Deliberate malicking pattern explained

### Migration Guide

If you have existing sessions with `prd.json`:

**Option 1: Manual conversion**
1. Open your existing `prd.json`
2. Create new `spec.md` following this template:

```markdown
# Session: [Your Session Name]

## Overview
[High-level description]

## Context & Requirements
[Detailed specs]

## Tasks

### ⬜ Task: task-id-from-json
**Priority:** high|medium|low
**Status:** incomplete

[Description from JSON]

**Acceptance:**
- [ ] [Acceptance criterion 1]
- [ ] [Acceptance criterion 2]

---
```

3. Delete old `prd.json`

**Option 2: Start fresh**
- Create a new session with `ralph init newsession`
- Copy your task list into the new `spec.md`

### Implementation Details

#### Base Prompt Changes
- Now explicitly lists files to read at start (context anchors)
- Instructs to update spec.md instead of prd.json
- Emphasizes minimal test output
- Clearer completion criteria

#### Session Init Changes
- Creates `spec.md` with example task format
- Improved `prompt.md` template with context anchor pattern
- Better inline documentation

#### Supervisor Integration
- New `run_supervisor()` function
- Runs after each successful iteration
- Can trigger one-off nudge iterations
- Preserves main loop state

### Best Practices (from HumanLayer Ralph Wiggum Showdown)

These changes incorporate best practices from the Ralph Wiggum methodology:

1. **Context windows are arrays** - Each iteration starts fresh
2. **One goal per context window** - Single task focus enforced
3. **Deliberate malicking** - Explicit file paths in context anchors
4. **Stay in the smart zone** - Token efficiency and headroom guidance
5. **Test runner optimization** - Only output failures
6. **Human on the loop** - Observation-driven tuning, not constant intervention
7. **Never blame the model** - Garbage in = garbage out philosophy
8. **Fireplace pattern** - Watch, notice, tune, repeat

### Files Changed

- `ralph.sh` - Core implementation
- `README.md` - Comprehensive documentation updates
- `skills/ralph-planner/SKILL.md` - Updated for spec.md format
- `examples/` - New directory with supervisor pattern examples

### Files Added

- `examples/supervisor-example.sh` - Example supervisor check script
- `examples/supervisor-nudge-example.md` - Example nudge prompt
- `examples/README.md` - Supervisor pattern documentation
- `CHANGELOG.md` - This file
