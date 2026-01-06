---
name: ralph-planner
description: Create or refine Ralph session plans by shaping work into a PRD JSON, initializing session files, and updating session prompt/progress without running Ralph. Use when the user asks to plan or shape work for a Ralph session, create a PRD for Ralph, or initialize a session context.
---

# Ralph Planner

## Overview
Prepare a Ralph session by shaping work into small, testable PRD items, creating the session scaffold, and writing session files. You are the **planner**—you set up the work, but you never execute it.

## Critical: Understanding the Separation

There are two distinct contexts at play. Confusing them causes bugs:

| Context | Who | When | What belongs here |
|---------|-----|------|-------------------|
| **Planner context** | You, right now | While this skill runs | Your workflow, guardrails, what commands to run/avoid |
| **Agent context** | Ralph agent | Later, during loop execution | Instructions for completing PRD tasks |

**The session files you create (`prompt.md`, `prd.json`, `progress.txt`) are read by the Ralph agent, not by you later.** Only write content relevant to that agent's task execution.

## Workflow (Planner Context)

1. **Gather inputs**
   - Repo root (current directory)
   - Session name (from user or infer from task)
   - Scope, goals, and acceptance criteria

2. **Initialize or open session**
   - Run: `ralph init <name>` or `./ralph.sh init <name>`
   - Session files live in `.agent/sessions/<name>/`
   - If session exists, read existing files before modifying

3. **Shape the PRD**
   - Break work into small, independent tasks (one feature/fix per item)
   - Each item must have specific, testable acceptance criteria
   - Set `passes: false` for all items

4. **Write session files**
   - Update `prd.json` with shaped tasks
   - Append planning notes to `progress.txt`
   - Update `prompt.md` with agent-relevant instructions only

5. **Hand back to user**
   - Summarize what was created/updated
   - Show the command to run Ralph (but do NOT run it yourself)

## PRD JSON Format

Array of task objects. Required fields:

```json
[
  {
    "id": "feature-login-form",
    "title": "Add login form",
    "description": "Users can sign in with email and password.",
    "acceptance": [
      "Form renders on /login",
      "Invalid credentials show error",
      "Successful login redirects to /dashboard"
    ],
    "priority": "high",
    "passes": false
  }
]
```

- `id`: kebab-case identifier
- `title`: short human-readable name
- `description`: one sentence explaining the task
- `acceptance`: 2-5 testable criteria
- `priority`: `high` | `medium` | `low`
- `passes`: always `false` (Ralph marks `true` after verification)

## Session prompt.md: What to Write

The `prompt.md` file provides instructions to the **Ralph agent** during task execution. Only include content that helps the agent complete PRD tasks.

**Good content for prompt.md:**
- Context anchors (key files to read before coding)
- Build/test commands specific to this work
- Scope constraints (what areas to touch or avoid)
- Coding conventions or patterns to follow
- External references (spec docs, API docs)

**Example:**
```markdown
Session context:
- PRD: .agent/sessions/auth-flow/prd.json
- Progress: .agent/sessions/auth-flow/progress.txt

Context anchors (read before coding):
- `specs/authentication.md` (auth requirements)
- `src/services/auth.ts` (existing auth service)
- `src/hooks/useAuth.ts` (auth hook interface)

Build commands:
- TypeScript: `pnpm typecheck`
- Tests: `pnpm test`
- If iOS touched: `xcodebuild -project App.xcodeproj -scheme App build`

Scope:
- Focus on `src/services/` and `src/hooks/`
- Do not modify database schema
```

## Session prompt.md: What NOT to Write

**Never write planner meta-instructions to session files.** These are for YOUR behavior, not the agent's:

| Bad (planner leak) | Why it's wrong |
|--------------------|----------------|
| "Do not run the Ralph loop" | Planner guardrail, not agent instruction |
| "Only prepare session artifacts" | Describes planner workflow, meaningless to agent |
| "Shape work into small tasks" | Planner process, agent executes existing tasks |
| "Hand back control to user" | Planner workflow step |

If you catch yourself writing instructions about "preparing", "planning", "shaping", or "not running"—stop. That's planner context leaking into agent context.

## Guardrails (Planner Context Only)

These rules govern YOUR behavior while running this skill. **Do not write these to any session file.**

- Never run `ralph`, `ralph.sh`, or any loop/`--once` command
- Never mark PRD items as `passes: true`
- Never delete or overwrite `progress.txt`—append only
- Never write planner workflow instructions to `prompt.md`
- Always explain where files are and how to run Ralph when done

## Progress File

Append-only log. Add a dated entry summarizing what you did:

```
2026-01-05 - Created session. Shaped 4 PRD items from auth epic. Added context anchors to prompt.
```

Do not delete previous entries. Do not write planner guardrails here.
