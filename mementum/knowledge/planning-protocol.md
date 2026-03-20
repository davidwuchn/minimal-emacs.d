---
title: Planning Protocol
status: active
category: protocol
tags: [planning, tasks, organization]
related: [mementum/state.md]
---

# Planning Protocol

File-based planning for complex tasks. Use when starting multi-step tasks (>5 tool calls).

## Core Principle

```
Context Window = RAM (volatile, limited)
Filesystem     = Disk (persistent, unlimited)
λ              = Transform intent → artifact

→ Anything important gets written to disk.
```

## First: Check for Previous Session

```bash
ls -la mementum/state.md 2>/dev/null
```

If resuming after session gap:
1. Read `mementum/state.md`
2. Run `git diff --stat` to see actual changes
3. Update state based on git state
4. Then proceed with task

## Memory Structure

| Location | Purpose | Content |
|----------|---------|---------|
| `mementum/state.md` | Session state | Current task, phase, next action |
| `mementum/memories/` | Findings | Atomic discoveries (<200 words each) |
| `mementum/knowledge/task-plan.md` | Task plan | Phase tracking, goals (create when needed) |

## Critical Rules

### 1. Create Plan First (τ — Wisdom)
Never start a complex task without updating `mementum/state.md`.

### 2. The 2-Action Rule (φ — Vitality)
> "After every 2 view/browser/search operations, IMMEDIATELY store key findings."

### 3. Read Before Decide (π — Synthesis)
Before major decisions, read `mementum/state.md`.

### 4. Update After Act (Δ — Change)
After completing any phase:
- Update state with: status, errors, files modified

### 5. Log ALL Errors (∀ — Vigilance)
Every error goes in state file. Prevents repetition.

### 6. Never Repeat Failures (∃ — Truth)
```
if action_failed:
    next_action ≠ same_action
```

## The 3-Strike Error Protocol

```
ATTEMPT 1: Diagnose & Fix
  → Read error carefully
  → Identify root cause
  → Apply targeted fix

ATTEMPT 2: Alternative Approach
  → Same error? Try different method
  → NEVER repeat exact same failing action

ATTEMPT 3: Broader Rethink
  → Question assumptions
  → Search for solutions

AFTER 3 FAILURES: Escalate to User
  → Explain what you tried
  → Share the specific error
```

## Read vs Write Decision

| Situation | Action |
|-----------|--------|
| Just wrote a file | DON'T read |
| Viewed image/PDF | Store findings NOW |
| Starting new phase | Read state first |
| Error occurred | Read relevant file |
| Resuming after gap | Read all state |

## The 5-Question Reboot Test (OODA)

| Question | Source |
|----------|--------|
| Where am I? | Current phase in state.md |
| Where am I going? | Remaining phases |
| What's the goal? | Goal statement |
| What have I learned? | memories/ |
| What have I done? | state.md history |

## Skip Criteria

Skip planning for:
- Single file edit
- Simple lookup question
- One-command operation
- No state changes required

## Anti-Patterns

| Don't | Do Instead |
|-------|-----------|
| Stuff everything in context | Store in mementum/ |
| Start executing immediately | Update state first |
| Repeat failed actions | Track attempts, mutate |
| Use vague phase names | Use verb-named, testable phases |