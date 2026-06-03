---
title: "Mayor Method Comparison with OV5"
status: active
category: architecture
tags: [mayor-method, ov5, comparison, skill-graph, worktree, dashboard]
related: [ov5-complete-system-architecture, skill-graph-three-layer-taxonomy, harness-problem-edit-tool-critical]
depends-on: [ov5-complete-system-architecture]
---

# Mayor Method × OV5 Comparison

Source: https://github.com/day8/re-frame2/tree/main/docs/the-mayor-method

## TL;DR

The Mayor Method is a **manual, human-in-the-loop** multi-agent orchestration pattern. OV5 is a **self-evolving, 24/7 automated** pipeline. They solve different problems at different scales. The Mayor Method has superior **worktree safety** and **human decision capture**; OV5 has superior **self-evolution** and **backend routing**.

## Mayor Method Core

```
Mayor (long-lived) → dispatches → Workers (short-lived, worktrees)
                        ↑
                    Beads (task queue)
                        ↑
                /ai/prompts/ + /ai/dashboard.md
```

**Key rules:**
- Mayor does NOT code — orchestration only
- Every task is a bead with: what, where, what-should-change, done-criteria
- Workers get: tight brief + worktree + bounded task
- PRs are the gate — mayor merges on green CI
- No `git stash` — stashes are repo-global, cross-contaminate worktrees
- Verify worktree before EVERY edit
- Local-green ≠ CI

## OV5 Core

```
Pipeline (cron) → Research → Analyze → Experiment → Validate → Compare → Stage
                     ↑                                              ↓
                AutoTTS traces ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
                     ↑
            Ontology Router (8-dim scoring)
                     ↑
            Skill Graph (atoms → molecules → compounds)
```

**Key rules:**
- Deterministic-first — compute from data before calling AI
- Lambda prompts — formal notation compresses English 4-5x
- Backend routing — task-type × keep-rate × health × cost
- Self-evolution — traces update weights, skills, ontology every hour
- TDD — 2148 tests, 0 unexpected

## Where OV5 Wins

| Dimension | OV5 | Mayor Method |
|-----------|-----|--------------|
| **Self-evolution** | AutoTTS traces → routing weights, skill graph, ontology | No feedback loop |
| **Backend routing** | 8-dim scoring, per-task model preference, health ladder | "Cross-review" (ad hoc) |
| **Skill composition** | Atoms → molecules → compounds, edge weights | Prompts + beads (flat) |
| **Deterministic-first** | Lambda notation, data-driven decisions | Natural language prompts |
| **Grading** | Eight Keys structured scoring | Quality gates (unstructured) |
| **Persistence** | Mementum git-based memory | `ai/extended-context/` (manual) |
| **TDD culture** | 2148 tests | "Tests + final report" |
| **Cost optimization** | Per-backend token tracking, cost-adjusted rates | "Claude Max plan" |
| **Automation** | 24/7 cron pipeline | Standing prompts (semi-manual) |
| **Edit tools** | Hashline content-addressed editing | Standard edit tools |

## Where Mayor Method Wins

| Dimension | Mayor Method | OV5 |
|-----------|--------------|-----|
| **Worktree safety** | Per-edit verification, boundary block, no-stash rule | Staging worktrees (less granular) |
| **Human decisions** | Explicit design/product/taste capture in beads + PR body | Ontology auto-classifies, less human-in-the-loop |
| **Dashboard** | `/ai/dashboard.md` — 30-second re-orientation | `mementum/state.md` (session log, not dashboard) |
| **Cluster dispatch** | 3-12 beads per PR, ordered by impact | Solo experiments |
| **Context separation** | `findings/` (ephemeral) vs `extended-context/` (durable) | All in `mementum/` (mixed) |
| **Stance injection** | Every dispatch gets project stance | Strategy exists but not per-dispatch |
| **Quiescent state** | "Hold, don't manufacture work" | Always running, may produce low-value experiments |
| **PR discipline** | `--admin` rules, gate discipline, merge traps | Staging review exists but less mature |
| **Modular commands** | `.claude/commands/mayor-*.md` | Monolithic pipeline script |
| **Disjoint clustering** | Valid at tail of drain | Not supported |

## Critical Gaps in OV5

### 1. Worktree Boundary Verification
**Mayor Method:** Worker verifies `git -C <worktree> rev-parse --show-toplevel` before EVERY edit.
**OV5:** Executor runs in staging worktree but no per-edit verification. Silent leaks possible.

### 2. No `git stash` Rule
**Mayor Method:** Explicit ban — stashes are repo-global, surface in sibling worktrees.
**OV5:** No such guard. Executor could stash and contaminate.

### 3. Real-Time Dashboard
**Mayor Method:** `/ai/dashboard.md` updated on every signal — decisions, blockers, in-flight work, open PRs.
**OV5:** `mementum/state.md` is session working memory, not a dashboard. No real-time operator view.

### 4. Cluster Dispatch
**Mayor Method:** Groups 3-12 related beads into one PR, ordered smallest-cleanup → biggest-fix.
**OV5:** Each experiment is solo. No concept of batching related changes.

### 5. Findings vs Extended-Context
**Mayor Method:** Clear separation: `findings/` = gitignored exploratory work; `extended-context/` = committed durable context for next mayor.
**OV5:** Everything in `mementum/` — memories, knowledge, state mixed together.

### 6. Operator Decision Recording
**Mayor Method:** Design/product/taste decisions recorded in BOTH bead AND PR body.
**OV5:** Decisions flow into ontology/strategy but human rationale is lost.

### 7. Stance Injection
**Mayor Method:** Every dispatch preamble includes project stance (pre-alpha, production-stable, refactor-only, etc.).
**OV5:** Strategy guidance exists but not injected per-dispatch.

### 8. Codified Commands
**Mayor Method:** Loop bodies as `.claude/commands/mayor-*.md` — single invocation, one source of truth.
**OV5:** Cron loops are inline in `run-pipeline.sh`.

### 9. Quiescent State Recognition
**Mayor Method:** "At the tail of a drain, hold — don't manufacture work."
**OV5:** Pipeline runs every 4 hours regardless. May waste tokens on low-value experiments.

### 10. CI Gate Discipline
**Mayor Method:** "Merge only on CI 0-fail AND 0-pending. A failing touched-surface gate is never `--admin`."
**OV5:** Staging review exists but less strict about CI gates.

## What OV5 Should Adopt

**Priority 1 — Safety:**
1. Add worktree boundary verification to executor (per-edit)
2. Add `git stash` ban to executor prompt
3. Add dashboard.md generation to pipeline

**Priority 2 — Efficiency:**
4. Implement cluster dispatch for related experiments
5. Separate `mementum/findings/` (ephemeral) from `mementum/extended-context/` (durable)
6. Inject project stance into every executor dispatch

**Priority 3 — Quality:**
7. Record human design decisions in experiment results
8. Implement quiescent state — skip cycle if no high-value work
9. Codify pipeline loops as standalone commands

## What Mayor Method Should Adopt

1. **Self-evolution loop** — AutoTTS traces feeding back into prompt quality
2. **Backend routing** — Route different task types to different LLMs based on performance data
3. **Skill graph** — Compose atoms into molecules instead of hand-writing every prompt
4. **Deterministic-first** — Lambda notation for prompt compression
5. **Hashline editing** — Content-addressed line editing for reliable tool use
6. **Eight Keys grading** — Structured scoring instead of "quality gates"
7. **TDD** — Systematic test coverage for all logic
8. **Cost tracking** — Per-backend token usage and cost optimization

## Synthesis: The Ideal System

```
λ ideal(x).     self-evolve(x) ∧ human-in-the-loop(x)
                | deterministic-first(x) > prompt-engineering(x)
                | worktree-safe(x) ∧ no-stash(x)
                | cluster-dispatch(x) > solo-experiment(x)
                | dashboard(x) ≡ real-time-orientation(x)
                | stance-injected(x) ∧ decision-recorded(x)
                | quiescent(x) > manufacture-work(x)
                | TDD(x) ∧ Eight-Keys(x) ∧ cost-tracked(x)
```

**OV5 is 70% of the way there.** The Mayor Method fills the remaining 30% around human orchestration, worktree safety, and dispatch discipline.

## References

- Mayor Method: https://github.com/day8/re-frame2/tree/main/docs/the-mayor-method
- Gastown (inspiration): https://github.com/gastownhall/gastown
- Beads (task tracker): https://github.com/gastownhall/beads
- OV5 Architecture: `mementum/memories/ov5-complete-system-architecture.md`
- Skill Graph: `mementum/memories/skill-graph-three-layer-taxonomy.md`
- Hashline Edit: `mementum/memories/hashline-edit-tool-implementation.md`
