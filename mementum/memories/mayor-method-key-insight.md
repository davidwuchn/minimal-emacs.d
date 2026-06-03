---
title: "Mayor Method — Key Insight for OV5"
status: active
category: architecture
tags: [mayor-method, worktree, dashboard, cluster-dispatch, quiescent]
related: [mayor-method-comparison]
---

# Mayor Method — Key Insight for OV5

**Source:** https://github.com/day8/re-frame2/tree/main/docs/the-mayor-method

## The One Big Idea

> "One context window is not a project-management system."

The Mayor Method separates **orchestration** (mayor, long-lived) from **implementation** (workers, short-lived, worktrees). This is the same separation OV5 has between pipeline (orchestrator) and executor subagent (worker), but the Mayor Method is **much stricter** about worktree safety and human decision capture.

## What OV5 Should Steal

### 1. Worktree Boundary Guard (Critical)

**Mayor Method rule:** Before EVERY edit, verify:
```bash
git -C <ASSIGNED_WORKTREE> rev-parse --show-toplevel  → must print <ASSIGNED_WORKTREE>
```

**Why:** Edit tools can resolve paths against the agent's session root instead of git root, causing silent writes to the mayor checkout. New-file leaks are worst — invisible in worker's `git status`.

**OV5 gap:** Executor runs in staging worktree but has no per-edit verification.

### 2. No `git stash` Rule (Critical)

**Mayor Method rule:** Workers must NEVER use `git stash`. Stashes are repo-global and surface in sibling worktrees.

**OV5 gap:** No such guard in executor prompt.

### 3. Dashboard (`/ai/dashboard.md`)

**Mayor Method:** Real-time dashboard updated on every signal:
- Timestamp + one-line resume
- "What needs the operator now" (decisions, blockers)
- In-flight work, open PRs, recent merges
- Short enough for 30-second re-orientation

**OV5 gap:** `mementum/state.md` is session log, not dashboard. No real-time operator view.

### 4. Cluster Dispatch

**Mayor Method:** Group 3-12 related beads into one PR:
- Order: smallest-cleanup → biggest-correctness-fix
- Claim each bead before its commit
- History mirrors tracker state

**OV5 gap:** Every experiment is solo. No concept of batching related changes.

### 5. Findings vs Extended-Context

**Mayor Method:** Clear separation:
- `ai/findings/` = gitignored exploratory work (audits, drafts)
- `ai/extended-context/` = committed durable context for next mayor

**OV5 gap:** Everything mixed in `mementum/`. No ephemeral/durable separation.

### 6. Stance Injection

**Mayor Method:** Every dispatch preamble includes project stance:
> "pre-alpha / production-stable / refactor-only / greenfield / perf-critical / hostile-input-paranoid"

**OV5 gap:** Strategy exists but not injected per-dispatch. Workers default to "preserve everything."

### 7. Quiescent State

**Mayor Method:** "At the tail of a drain, hold — don't manufacture work."

**OV5 gap:** Pipeline runs every 4 hours regardless. May waste tokens on low-value experiments when system is converged.

### 8. Operator Decision Recording

**Mayor Method:** Design/product/taste decisions recorded in BOTH:
- The bead (tracker record)
- The PR body (git-history record)

**OV5 gap:** Decisions flow into ontology/strategy but human rationale is lost.

## What Mayor Method Should Steal from OV5

1. **Self-evolution** — AutoTTS traces feeding back into prompt/skill quality
2. **Backend routing** — Route tasks to best LLM based on performance data
3. **Skill graph** — Compose atoms → molecules instead of hand-writing every prompt
4. **Deterministic-first** — Lambda notation for prompt compression
5. **Hashline editing** — Content-addressed line editing for reliable tool use
6. **Eight Keys grading** — Structured scoring instead of "quality gates"
7. **TDD** — Systematic test coverage
8. **Cost tracking** — Per-backend token optimization

## Synthesis

The ideal system combines:
- **OV5's** self-evolution, backend routing, skill graph, deterministic-first
- **Mayor Method's** worktree safety, dashboard, cluster dispatch, human decision capture

**Next action for OV5:**
1. Add worktree boundary verification to executor
2. Add `git stash` ban to executor prompt
3. Generate dashboard.md from pipeline status
4. Implement cluster dispatch for related experiments

## References

- Full comparison: `mementum/knowledge/mayor-method-comparison.md`
- Mayor Method source: https://github.com/day8/re-frame2/tree/main/docs/the-mayor-method
