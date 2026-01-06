---
name: ralph-planner
description: Create or refine Ralph session plans by shaping work into spec.md, initializing session files, and updating session prompt/progress without running Ralph. Use when the user asks to plan or shape work for a Ralph session, create a spec for Ralph, or initialize a session context.
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

**The session files you create (`prompt.md`, `spec.md`, `progress.txt`) are read by the Ralph agent, not by you later.** Only write content relevant to that agent's task execution.

## Workflow (Planner Context)

1. **Gather inputs**
   - Repo root (current directory)
   - Session name (from user or infer from task)
   - Scope, goals, and acceptance criteria

2. **Initialize or open session**
   - Run: `ralph init <name>` or `./ralph.sh init <name>`
   - Session files live in `.agent/sessions/<name>/`
   - If session exists, read existing files before modifying

3. **Shape the spec**
   - Break work into small, independent tasks (one feature/fix per item)
   - Each task must have specific, testable acceptance criteria
   - Mark all tasks with ⬜ status (incomplete)
   - Use checkbox format `- [ ]` for acceptance criteria

4. **Write session files**
   - Update `spec.md` with shaped tasks
   - Append planning notes to `progress.txt`
   - Update `prompt.md` with agent-relevant instructions and context anchors

5. **Hand back to user**
   - Summarize what was created/updated
   - Show the command to run Ralph (but do NOT run it yourself)

## Spec.md Format

Markdown file combining specs and task checklist. Tasks use this format:

```markdown
# Session: Feature Name

## Overview
High-level description of what we're building and why.

## Context & Requirements
Detailed specs, design decisions, API contracts, constraints.

## Tasks

### ⬜ Task: feature-login-form
**Priority:** high
**Status:** incomplete

Users can sign in with email and password.

**Acceptance:**
- [ ] Form renders on /login
- [ ] Invalid credentials show error
- [ ] Successful login redirects to /dashboard

**Notes:**
Use existing AuthService, follow form patterns in /components/forms.

---

### ⬜ Task: another-task
**Priority:** medium
**Status:** incomplete

...

---
```

**Task format:**
- Status emoji: `⬜` (incomplete) or `✅` (complete)
- Task ID after "Task:" (kebab-case)
- Priority: high | medium | low
- Status: incomplete | complete
- Checkbox acceptance criteria `- [ ]` / `- [x]`
- Optional notes section for implementation hints

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
# Context Anchors (read these first)
These files contain the source of truth for this work:
- `spec.md` - session spec with all tasks
- `specs/authentication.md` - auth requirements and flows
- `src/services/auth.ts` - existing auth implementation
- `src/hooks/useAuth.ts` - auth hook interface

**Why explicit anchors work:** Mentioning file paths triggers the model to read them.
Order matters—read specs first, then implementation files.

# Build Commands
- Typecheck: `pnpm typecheck`
- Tests: `pnpm test --bail` (only show failures to save tokens)
- iOS (if touched): `xcodebuild -project App.xcodeproj -scheme App build`

# Scope
- Modify: `src/services/auth/`, `src/hooks/`
- Do NOT touch: database migrations, CI config

# Conventions
- Use existing AuthService patterns
- Follow form patterns in `src/components/forms/`
- All auth errors should use AuthError type
```

**This is "deliberate malicking"** - explicitly listing files forces the model to read them
at the start of each iteration, keeping critical context in the "smart zone."

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
