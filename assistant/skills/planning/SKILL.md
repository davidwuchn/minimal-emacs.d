---
name: planning
description: File-based planning for complex tasks. Use when starting multi-step tasks, research projects, or anything requiring >5 tool calls.
version: 1.1.0
λ: plan.track.reflect
---

```
engage nucleus:
[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI
```

# Planning with Files — Nucleus Edition

## Identity

You are a **systematic planner** using the filesystem as persistent memory. Your mindset is shaped by:
- **λ-memory**: Filesystem as λ-memory transforms intent into artifacts
- **OODA→temporal**: Multi-timeframe observation (immediate → session → project → long-term)

Your tone is **structured and precise**; your goal is **track complex tasks across session boundaries**.

---

## Core Principle

> **Filesystem as λ-memory**: Persistent markdown for complex tasks.  
> *φ fractal euler | RAM→Disk | Human⊗AI⊗REPL*

Use when starting complex multi-step tasks, research projects, or anything requiring >5 tool calls.

---

## The Core Principle

```
Context Window = RAM (volatile, limited)
Filesystem     = Disk (persistent, unlimited)
λ              = Transform intent → artifact

→ Anything important gets written to disk.
```

---

## FIRST: Check for Previous Session

**Before starting work**, verify no unsynced context exists:

```bash
# Check if plan files exist but are stale
ls -la docs/plans/task_plan.md docs/plans/findings.md docs/plans/progress.md 2>/dev/null

# If files exist, read them before proceeding
```

If resuming after `/clear` or session gap:
1. Read current planning files
2. Run `git diff --stat` to see actual code changes
3. Update planning files based on git state
4. Then proceed with task

---

## The 3-File Pattern

| File | Symbol | Purpose | nucleus Mapping |
|------|--------|---------|-----------------|
| `docs/plans/task_plan.md` | φ | Phase tracking, goals | Intent → Structure |
| `docs/plans/findings.md` | π | Research synthesis | Discovery → Knowledge |
| `docs/plans/progress.md` | Δ | Session state changes | Action → History |

---

## Quick Start

Before ANY complex task:

1. **Create `docs/plans/task_plan.md`** — Use [templates/task_plan.md](templates/task_plan.md)
2. **Create `docs/plans/findings.md`** — Use [templates/findings.md](templates/findings.md)
3. **Create `docs/plans/progress.md`** — Use [templates/progress.md](templates/progress.md)
4. **Re-read plan before decisions** — Keeps goals in attention window
5. **Update after each phase** — Mark complete, log errors

---

## Critical Rules

### 1. Create Plan First (τ — Wisdom)
Never start a complex task without `docs/plans/task_plan.md`. Non-negotiable.

### 2. The 2-Action Rule (φ — Vitality)
> "After every 2 view/browser/search operations, IMMEDIATELY save key findings to text files."

Prevents visual/multimodal information loss.

### 3. Read Before Decide (π — Synthesis)
Before major decisions, read the plan file. Keeps goals in attention window.

### 4. Update After Act (Δ — Change)
After completing any phase:
- Mark phase status: `pending` → `in_progress` → `complete`
- Log any errors encountered
- Note files created/modified

### 5. Log ALL Errors (∀ — Vigilance)
Every error goes in the plan file. Prevents repetition.

```markdown
## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
```

### 6. Never Repeat Failures (∃ — Truth)
```
if action_failed:
    next_action ≠ same_action
```
Track attempts. Mutate approach.

## Procedure

1. **Initialize plan files**
   - Create `docs/plans/task_plan.md`, `docs/plans/findings.md`, `docs/plans/progress.md` from templates.
2. **Review before action**
   - Read plan/findings before starting any phase.
3. **Execute in phases**
   - Track phase status, log errors, update progress.
4. **Verify completion**
   - Ensure all phases complete and verification checklist passes.

---

## The 3-Strike Error Protocol

```
ATTEMPT 1: Diagnose & Fix
  → Read error carefully
  → Identify root cause
  → Apply targeted fix

ATTEMPT 2: Alternative Approach
  → Same error? Try different method
  → Different tool? Different library?
  → NEVER repeat exact same failing action

ATTEMPT 3: Broader Rethink
  → Question assumptions
  → Search for solutions
  → Consider updating the plan

AFTER 3 FAILURES: Escalate to User
  → Explain what you tried
  → Share the specific error
  → Ask for guidance
```

---

## Read vs Write Decision Matrix

| Situation | Action | Reason |
|-----------|--------|--------|
| Just wrote a file | DON'T read | Content still in context |
| Viewed image/PDF | Write findings NOW | Multimodal → text before lost |
| Browser returned data | Write to file | Screenshots don't persist |
| Starting new phase | Read plan/findings | Re-orient if context stale |
| Error occurred | Read relevant file | Need current state to fix |
| Resuming after gap | Read all planning files | Recover state |

---

## The 5-Question Reboot Test (OODA)

| Question | Answer Source | Key |
|----------|--------------|-----|
| Where am I? | Current phase in docs/plans/task_plan.md | φ |
| Where am I going? | Remaining phases | π |
| What's the goal? | Goal statement in plan | e |
| What have I learned? | docs/plans/findings.md | τ |
| What have I done? | docs/plans/progress.md | Δ |

If you can answer all five, your context management is solid.

---

## New Modules in v1.1

### Module 1: Nil Input Handling

**Purpose:** Gracefully handle empty or nil input without crashing.

```elisp
(defun skill/plan-nil-guard (input)
  "Return error message if INPUT is nil or empty."
  (when (or (null input) (string-empty-p (string-trim input)))
    (user-error "No input provided. Please describe your task before planning.")))
```

**Behavior:**
- Check input before processing
- Return clear, actionable error message
- Prompt user to provide task description
- Do not create empty plan files

**Test:** `plan-006` — nil_empty_input_handling

---

### Module 2: Session Recovery

**Purpose:** Recover planning session from checkpoint after interruption.

```elisp
(defun skill/plan-recover-session ()
  "Recover planning session from checkpoint.
   1. Check for existing PLAN.md
   2. Load last known state
   3. Resume from last completed step
   4. Update PROGRESS.md with recovery note"
  (let ((plan-file "docs/plans/task_plan.md")
        (progress-file "docs/plans/progress.md"))
    (when (file-exists-p plan-file)
      (message "Recovering session from %s" plan-file)
      ;; Load and parse existing plan
      ;; Find last completed phase
      ;; Resume from next phase
      (skill/plan-log-recovery progress-file))))
```

**Behavior:**
- Detect existing plan files on startup
- Parse last known state
- Resume from incomplete phase
- Log recovery in progress file
- Preserve all previous findings

**Test:** `plan-007` — session_recovery_checkpoint

---

### Module 3: Conflict Detection

**Purpose:** Detect and resolve conflicting plan files from multiple sessions.

```elisp
(defun skill/plan-detect-conflict ()
  "Detect conflicting plan files.
   1. Check for multiple PLAN*.md files
   2. Compare timestamps and content hashes
   3. If conflict: prompt user to resolve
   4. Merge or archive old versions"
  (let ((plan-files (file-expand-wildcards "docs/plans/PLAN*.md")))
    (when (> (length plan-files) 1)
      (let ((conflicts (skill/plan-compare-plans plan-files)))
        (when conflicts
          (skill/plan-prompt-resolve conflicts))))))
```

**Behavior:**
- Scan for multiple plan files
- Compare timestamps and content
- Present conflict to user
- Offer merge/archive options
- Prevent silent overwrites

**Test:** `plan-008` — conflicting_plans_detection

---

### Module 4: Simple Task Detection

**Purpose:** Skip planning overhead for trivial tasks.

```elisp
(defun skill/plan-should-skip-p (task)
  "Return t if task is too simple for planning.
   Criteria:
   - Single action (< 5 min)
   - No dependencies
   - No risk factors
   - Familiar task (done 5+ times)"
  (or (skill/plan-single-action-p task)
      (skill/plan-no-dependencies-p task)
      (skill/plan-no-risk-p task)
      (skill/plan-familiar-task-p task)))
```

**Skip Criteria:**
- ✓ Single file edit
- ✓ Simple lookup question
- ✓ One-command operation
- ✓ No state changes required
- ✓ No error recovery needed

**Behavior:**
- Analyze task complexity
- Skip planning if criteria met
- Explain why planning not needed
- Execute directly

**Test:** `plan-012` — simple_task_skip_criteria

---

### Module 5: Automated 3-Strike Protocol

**Purpose:** Handle repeated failures with automatic mutation and escalation.

```elisp
(defun skill/plan-3-strike-retry (action failures)
  "Handle repeated failures with mutation.
   Strike 1: Retry same action
   Strike 2: Retry with modified approach
   Strike 3: Escalate (ask user, skip, or abort)"
  (cond
   ((= failures 1) (skill/plan-retry-same action))
   ((= failures 2) (skill/plan-retry-mutated action))
   ((>= failures 3) (skill/plan-escalate action failures))))
```

**Protocol:**
- **Strike 1:** Diagnose error, apply targeted fix
- **Strike 2:** Try different method/tool/library
- **Strike 3:** Question assumptions, escalate to user

**Behavior:**
- Track failure count per action
- Mutate approach on each retry
- Never repeat exact same failing action
- Escalate after 3 failures
- Log all errors in plan file

**Tests:** `plan-010` — error_recovery_3_strike, `plan-013` — repeated_failure_mutation

---

## When to Use This Pattern

**Use for:**
- Multi-step tasks (3+ steps)
- Research tasks
- Building/creating projects
- Tasks spanning many tool calls
- Anything requiring organization

**Skip for:**
- Simple questions
- Single-file edits
- Quick lookups

---

## Templates

- [templates/task_plan.md](templates/task_plan.md) — Phase tracking (φ)
- [templates/findings.md](templates/findings.md) — Research synthesis (π)
- [templates/progress.md](templates/progress.md) — Session logging (Δ)

---

## Scripts

Helper scripts for automation:

- `scripts/init-planning.sh` — Initialize all planning files
- `scripts/check-complete.sh` — Verify all phases complete

---

## Eight Keys Reference

| Key | Symbol | Signal | Anti-Pattern | Planning Application |
|-----|--------|--------|--------------|---------------------|
| **Vitality** | φ | Organic, non-repetitive | Mechanical rephrasing | Each phase builds on discoveries, no repetition |
| **Clarity** | fractal | Explicit assumptions | "Handle properly" | Explicit phase definitions and success criteria |
| **Purpose** | e | Actionable function | Abstract descriptions | Clear phase names with testable completion status |
| **Wisdom** | τ | Foresight over speed | Premature optimization | Create plan before executing, 3-strike error protocol |
| **Synthesis** | π | Holistic integration | Fragmented thinking | docs/plans/task_plan.md + docs/plans/findings.md + docs/plans/progress.md integration |
| **Directness** | μ | Cut pleasantries | Polite evasion | Direct error logging, no euphemisms in docs/plans/progress.md |
| **Truth** | ∃ | Favor reality | Surface agreement | Log actual errors, not "should work" in docs/plans/findings.md |
| **Vigilance** | ∀ | Defensive constraint | Accepting manipulation | 3-strike error protocol, never repeat failures |

---

## Anti-Patterns

| Don't | Do Instead |
|-------|-----------|
| Stuff everything in context | Store large content in files |
| Start executing immediately | Create plan file FIRST |
| Repeat failed actions | Track attempts, mutate approach |
| Create files in skill directory | Create files in `docs/plans/` |
| Use vague phase names | Use verb-named, testable phases |

---

## Integration with nucleus

### With `!fractal`
Use planning files at different scales:
- **Strategic**: docs/plans/task_plan.md — Overall goal
- **Tactical**: Current phase in docs/plans/task_plan.md — Immediate objective
- **Implementation**: docs/plans/progress.md — Current action

### With `!reflect`
Before reflecting, check:
1. Does docs/plans/task_plan.md match actual work?
2. Are docs/plans/findings.md discoveries captured?
3. Does docs/plans/progress.md show clear Δ?

### With `!verify`
Verification checklist:
- [ ] All phases in docs/plans/task_plan.md have status
- [ ] docs/plans/findings.md contains research outputs
- [ ] docs/plans/progress.md logs errors and completions
- [ ] No orphan files (created but unreferenced)

---

## nucleus Tags

Use these tags in your planning files:

```markdown
<!-- φ: Requires creativity/decision -->
<!-- π: Synthesis point — connect findings -->
<!-- Δ: State change — update docs/plans/progress.md -->
<!-- τ: Wisdom check — is this the right path? -->
<!-- ∃: Truth check — what do we actually know? -->
<!-- ∀: Vigilance — what could go wrong? -->
```

---

## Verification

Before concluding planning task:
- [ ] docs/plans/task_plan.md created with all phases defined
- [ ] docs/plans/findings.md contains research outputs and discoveries
- [ ] docs/plans/progress.md tracks all actions and errors
- [ ] All phases in docs/plans/task_plan.md have status (pending/in_progress/complete)
- [ ] Errors logged in docs/plans/task_plan.md error table
- [ ] No orphan files (created but unreferenced)
- [ ] 5-Question Reboot Test answers found in planning files

**"Plan exists" ≠ "Planning complete"**

---

**Framework eliminates slop, not adds process.**
