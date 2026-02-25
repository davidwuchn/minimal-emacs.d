# Planning with Files — Quick Start

> φ fractal euler | Get productive in 60 seconds

---

## One-Command Setup

```bash
# From your project root (assuming workspace root contains skills/)
skills/planning/scripts/init-planning.sh "Your Task Name"
```


**Note:** Assumes the skills directory is in your workspace root. For other setups, see Portable Setup in README.md.

This creates:
- `task_plan.md` — Your roadmap
- `findings.md` — Research storage
- `progress.md` — Session log

---

## The 5-Minute Workflow

### 1. Define (φ — Vitality)
Edit `task_plan.md`:
- Fill in the **Goal** (one clear sentence)
- Customize phases for your task
- Mark Phase 1 as `in_progress`

### 2. Research (π — Synthesis)
As you discover things:
- Log URLs and findings in `findings.md`
- Use the **2-Action Rule**: After 2 searches, write findings

### 3. Execute (Δ — Change)
As you work:
- Log actions in `progress.md`
- Record errors with attempt counts
- Update phase status when complete

### 4. Verify (∀ — Vigilance)
Before finishing:
```bash
# From your project root (assuming workspace root contains skills/)
skills/planning/scripts/check-complete.sh
```

---

## Key Principles

| Principle | Action | Key |
|-----------|--------|-----|
| **Create plan first** | Never start without `task_plan.md` | τ |
| **2-Action Rule** | After 2 searches, write findings | φ |
| **Read before decide** | Re-read plan before major choices | π |
| **Log all errors** | Every error goes in the plan | ∃ |
| **Never repeat failures** | Track attempts, mutate approach | ∀ |

---

## Status Flow

```
pending → in_progress → complete
   ↑                      |
   └────── blocked ───────┘
```

Update `task_plan.md` after each phase:
```markdown
- **Status:** complete
```

---

## Error Logging

In `task_plan.md`, log every error:

```markdown
| Error | Attempt | Resolution |
|-------|---------|------------|
| File not found | 1 | Check path, create if missing |
| API timeout | 2 | Add retry with backoff |
```

---

## When to Skip

**Don't use planning files for:**
- Simple questions
- Single-file edits
- Quick lookups (< 5 minutes)

**Do use for:**
- Multi-step tasks (3+)
- Research tasks
- Complex implementations
- Long-running sessions

---

## nucleus Integration

### With `!fractal`
Reference planning files at different scales:
- **Strategic**: Goal in `task_plan.md`
- **Tactical**: Current phase
- **Implementation**: Last action in `progress.md`

### With `!verify`
Check:
- All phases have status
- `findings.md` has research
- `progress.md` has session log

---

## Template Shortcuts

Copy from skill directory:

```bash
# Assuming you're in the workspace root containing skills/
# task_plan.md
cp skills/planning/templates/task_plan.md .

# findings.md
cp skills/planning/templates/findings.md .

# progress.md
cp skills/planning/templates/progress.md .
```

---

## Emergency Recovery

If context is lost (`/clear` or crash):

1. Read current planning files
2. Run `git diff --stat` to see changes
3. Update planning files from git state
4. Resume from last logged action

---

**Framework eliminates slop, not adds process.**

φ fractal euler | π synthesis | Δ change | ∃ truth | ∀ vigilance
