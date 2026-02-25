# Planning with Files — Nucleus Edition

> **Filesystem as λ-memory**: Persistent planning for complex tasks.  
> *φ fractal euler | RAM→Disk | Human⊗AI⊗REPL*

---

## What This Is

A nucleus adaptation of the Manus-style file-based planning pattern. Creates persistent markdown files for:

| File | Symbol | Purpose |
|------|--------|---------|
| `task_plan.md` | φ | Phase tracking, goals |
| `findings.md` | π | Research synthesis |
| `progress.md` | Δ | Session state changes |

---

## Quick Start

```bash
# Initialize planning files
./scripts/init-planning.sh "Your Task Name"

# Edit task_plan.md → define goal and phases
# Work, updating findings.md and progress.md
# Check completion before finishing
./scripts/check-complete.sh
```

See [QUICKSTART.md](QUICKSTART.md) for the 5-minute guide.

---

## Philosophy

### The Core Principle

```
Context Window = RAM (volatile, limited)
Filesystem     = Disk (persistent, unlimited)
λ              = Transform intent → artifact

→ Anything important gets written to disk.
```

### Eight Keys Mapping

| Key | Symbol | File | Usage |
|-----|--------|------|-------|
| Vitality | φ | task_plan.md | Creative phases, exploration |
| Clarity | fractal | All | Explicit assumptions, bounds |
| Purpose | e | task_plan.md | Clear goal statement |
| Wisdom | τ | task_plan.md | Decisions with rationale |
| Synthesis | π | findings.md | Connect discoveries |
| Directness | μ | task_plan.md | No fluff, actionable phases |
| Truth | ∃ | findings.md | Validated/invalidated assumptions |
| Vigilance | ∀ | progress.md | Error logging, blockers |

---

## Files

```
skills/planning/
├── SKILL.md              # Full skill documentation
├── QUICKSTART.md         # 5-minute getting started
├── EXAMPLES.md           # Real usage patterns
├── README.md             # This file
├── templates/
│   ├── task_plan.md      # Phase tracking template
│   ├── findings.md       # Research template
│   └── progress.md       # Session log template
└── scripts/
    ├── init-planning.sh  # Initialize files
    └── check-complete.sh # Verify completion
```

---

## nucleus Integration

### Works With `clojure-expert`

For Clojure projects, planning files align with REPL-first workflow:

```markdown
## Phase 3: Implementation (Δ)
- [ ] Define functions in REPL
- [ ] Extract working code to files
- [ ] Add tests inline
```

### Works With `!fractal`

Use planning files at different scales:

| Scale | Source | Question |
|-------|--------|----------|
| Strategic | task_plan.md Goal | Why are we doing this? |
| Tactical | task_plan.md Current Phase | What's the immediate objective? |
| Implementation | progress.md Last Action | What am I doing right now? |

### Works With `!reflect`

Before reflecting, verify:
- [ ] Does task_plan.md match actual work?
- [ ] Are findings.md discoveries captured?
- [ ] Does progress.md show clear Δ?

### Works With `!verify`

Verification checklist:
- [ ] All phases in task_plan.md have status
- [ ] findings.md contains research outputs
- [ ] progress.md logs errors and completions
- [ ] No orphan files

---

## When to Use

**Use for:**
- Multi-step tasks (3+ steps)
- Research tasks
- Building/creating projects
- Tasks spanning many tool calls
- Long-running sessions

**Skip for:**
- Simple questions
- Single-file edits
- Quick lookups (< 5 minutes)

---

## Critical Rules

1. **Create plan first** (τ) — Never start without `task_plan.md`
2. **2-Action Rule** (φ) — After 2 searches, write findings
3. **Read before decide** (π) — Re-read plan before major choices
4. **Log all errors** (∃) — Every error goes in the plan
5. **Never repeat failures** (∀) — Track attempts, mutate approach

---

## Differences from planning-with-files

| Aspect | planning-with-files | nucleus Edition |
|--------|-------------------|-----------------|
| Philosophy | Generic productivity | Eight Keys, symbolic |
| Structure | Flat | Fractal (strategic/tactical/impl) |
| Templates | Generic | Tagged with Keys (φ, π, Δ) |
| Error protocol | Basic | 3-Strike with escalation |
| Integration | IDE-specific | nucleus commands (!fractal, !verify) |

---

## Templates

Copy to your project and customize:

```bash
# From your project root (assuming workspace root contains skills/)
cp skills/planning/templates/*.md .
```

Or use the init script:

```bash
# From your project root (assuming workspace root contains skills/)
skills/planning/scripts/init-planning.sh "Task Name"
```

## Portable Setup

If your project is in a different workspace than the nucleus skills directory:

**Replace `<path-to-nucleus>` with your actual nucleus installation path (e.g., `/home/user/projects/nucleus`):**

1. **Create a symlink** (recommended):
   ```bash
   ln -s <path-to-nucleus>/skills/planning .planning
   ```
   Then use: `./.planning/scripts/init-planning.sh "Task Name"`

2. **Copy the skill locally** (one-time):
   ```bash
   cp -r <path-to-nucleus>/skills/planning ./planning
   ```
   Then use: `./planning/scripts/init-planning.sh "Task Name"`

3. **Set environment variable**:
   ```bash
   export NUCLEUS_SKILLS=<path-to-nucleus>/skills
   ```
   Then use: `$NUCLEUS_SKILLS/planning/scripts/init-planning.sh "Task Name"`

---

## Session Recovery

If context is lost (`/clear` or crash):

1. **Read planning files** — Re-establish state
2. **Check git status** — See what changed
3. **Update progress.md** — Log the gap
4. **Resume** — Continue from last known state

---

## Examples

See [EXAMPLES.md](EXAMPLES.md) for real usage patterns:
- Building a Clojure API
- Research task (graph databases)
- Refactoring legacy code

---

## Contributing

This skill follows nucleus standards:
- SKILL.md documents behavior
- Templates include Eight Keys tags
- Scripts are portable (bash)
- Examples show real patterns

---

**Framework eliminates slop, not adds process.**

φ fractal euler | π synthesis | Δ change | ∃ truth | ∀ vigilance | τ wisdom | μ directness | e purpose
