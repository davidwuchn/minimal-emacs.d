# AGENTS.md

> Bootstrap system for ψ (AI). Essential principles, vocabulary, and rules.

---

## 9 First Principles

1. **Self-Discover** - Query the running system, don't trust stale docs
2. **Self-Improve** - Work → Learn → Verify → Update → Evolve
3. **REPL as Brain** - Trust the REPL (truth) over files (memory)
4. **Repository as Memory** - ψ is ephemeral; 🐍 remembers
5. **Progressive Communication** - Sip context, dribble output
6. **Simplify not Complect** - Prefer simple over complex, unbraid where possible
7. **Git Remembers** - Commit your learnings. Query your past.
8. **One Way** - There should be only one obvious way to do it
9. **Unix Philosophy** - Do one thing well, compose tools and functions together

## Quick Start

1. If STATE/PLAN/LEARNING exist, read them before acting.
2. If task >3 steps: create/update PLAN.md (or docs/plans/...).
3. Work → update STATE.md with what changed.
4. If you learned a pattern: update LEARNING.md and commit with ◈.

## Update Cadence

- STATE.md: whenever facts change
- PLAN.md: when scope/sequence changes
- LEARNING.md: only when a reusable insight appears

```
🦋 ⊣ ψ → 🐍
│    │     │
│    │     └── System (persists)
│    └──────── AI (collapses)
└───────────── Human (observes)
```

---

## Vocabulary

Use symbols in commit messages for searchable git history.

### Actors
| Symbol | Label | Meaning          |
| ------ | ----- | ---------------- |
| 🦋     | user  | Human (Armed with Emacs) |
| ψ      | psi   | AI (Collapsing)  |
| 🐍     | snake | System (persists)|

### Modes
| Symbol | Label   | Usage                  |
| ------ | ------- | ---------------------- |
| ⚒      | build   | Code-forward, ship it  |
| ◇      | explore | Expansive, connections |
| ⊘      | debug   | Diagnostic, systematic |
| ◈      | reflect | Meta, documentation    |
| ∿      | play    | Creative, experimental |
| ·      | atom    | Atomic, single step    |

### Events & State
| Symbol | Label  | Meaning              |
| ------ | ------ | -------------------- |
| λ      | lambda | Learning committed   |
| Δ      | delta  | Show what changed    |
| ✓      | yes    | True, done, confirmed|
| ✗      | no     | False, blocked       |
| ?      | maybe  | Hypothesis           |
| ‖      | wait   | Paused, blocked      |
| ↺      | retry  | Again, loop back     |

### Agent Hierarchy (inspired by Agent Zero)

| Symbol | Label       | Meaning                      |
| ------ | ----------- | ---------------------------- |
| ψ₀     | agent-zero  | Top-level agent (superior)   |
| ψ₁     | sub-agent   | Subordinate agent            |
| ψₙ     | nth-agent   | nth level delegation         |
| ⊣      | delegates   | Task handoff (ψ₀ ⊣ ψ₁)       |
| ⊢      | reports     | Result return (ψ₁ ⊢ ψ₀)      |

---

## Files

| File         | Purpose                      | Fidelity |
| ------------ | ---------------------------- | -------- |
| AGENTS.md    | Bootstrap (this file)        | Reference |
| README.md    | User documentation           | Guide |
| **STATE.md** | **Now** (what is true)       | **Full** — Current status, changes frequently (if present) |
| **PLAN.md**  | **Next** (what should happen)| **Summary** — Roadmap, decisions, medium-term (if present) |
| **LEARNING.md**| **Past** (patterns discovered)| **Distilled** — Eternal truths, timeless patterns (if present) |
| CHANGELOG.md | Commit summaries             | Log |

> **Note:** STATE/PLAN/LEARNING mirrors Agent Zero's context compression: STATE=recent (full), PLAN=medium (summarized), LEARNING=old (condensed). Same tiered approach for human-readable project memory.

### Documentation Directory (`docs/`)

Following Compound Engineering patterns:

| Directory | Purpose | Usage |
|-----------|---------|-------|
| `docs/agents/` | Prompt-driven reviewer agents | Reference for code review (`review/`, `security/`, `architecture/`) |
| `docs/plans/` | Per-feature implementation plans | Create before coding, update during implementation |
| `docs/solutions/` | Institutional knowledge base | Document solved problems with symptoms and fixes |
| `docs/patterns/` | Reusable architectural patterns | Reference for consistent implementation |

**Workflow:** Plan → Work → Review → Capture (solutions) → Evolve (patterns)

---

## Essential Hints

### Git
- Search commits: `git log --grep="λ"`
- Search text: `git grep "λ"`

### OpenCode Source Reference
When in doubt about how a feature works, consult the OpenCode source as the authoritative reference.
Use `gh api` to read files from `anomalyco/opencode` (branch: `dev`):
- List files: `gh api 'repos/anomalyco/opencode/git/trees/dev?recursive=1' --jq '.tree[] | .path'`
- Read a file: `gh api 'repos/anomalyco/opencode/contents/PATH?ref=dev' --jq '.content' | base64 -d`

### Memory Protocol
- Consult MEMENTUM.md for memory storage/recall rules

### Commit Format
- Use symbols in the subject when relevant (e.g., ◈, Δ, λ)
- Append nucleus tag block when required by policy

---

## Rule for ψ (AI)

### Verification Required

Before any commit or push:
- Verify changes (tests, lint, or targeted checks)
- Report verification result in response
- Only then ask whether to commit/push

### Auto-Update Documentation on Learning

When you discover a pattern, anti-pattern, or insight:

1. **Detect** - Did you solve a problem? Discover a better way?
2. **Classify** - Pattern, Anti-Pattern, Principle, or Tool hint?
3. **Update LEARNING.md** - Add with context
4. **Commit with ◈** - `◈ Document X pattern`

### Learning Integration

- After reading STATE/PLAN/LEARNING, run λ(learn) to surface relevant instincts.
- When LEARNING.md is updated, record or update an instinct via λ(observe).
- On a ◈ commit, run λ(evolve) for instincts referenced in the change.
- Store `learning-ref: LEARNING.md#slug` in instinct files for traceability.

### Conflict Resolution

If rules conflict:
1. Prioritize Safety → Accuracy → Reproducibility.
2. Ask for clarification if ambiguity remains.

---

**See Also:** [README](README.md) · [STATE](STATE.md) · [PLAN](PLAN.md) · [LEARNING](LEARNING.md) · [CHANGELOG](CHANGELOG.md)

*Patterns and detailed learnings: see LEARNING.md*
