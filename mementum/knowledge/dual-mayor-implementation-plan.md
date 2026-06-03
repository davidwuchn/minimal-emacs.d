---
title: "Dual Mayor Implementation Plan"
status: planning
category: implementation
tags: [dual-mayor, plan, PMF, GTM, roadmap]
related: [dual-mayor-architecture]
depends-on: [dual-mayor-architecture]
---

# Dual Mayor Implementation Plan

**Design:** `mementum/knowledge/dual-mayor-architecture.md`
**Status:** Planning → Ready to implement

## Current State

- ✅ Design complete: Dual Mayor Architecture
- ✅ Naming: PMF Mayor (auto-workflow), GTM Mayor (researcher)
- ✅ Frameworks: PLG 5-step (PMF), JTBD/ODI 5-step (GTM)
- ✅ Innovation principles: Resolution Refined, Struggle Well
- ✅ Method names: 快速拉新建构组织 (PMF), 闪电扩张解构文化 (GTM)
- 🔴 Researcher still shuts down after completion (not persistent)
- 🔴 No dashboards (product-dashboard.md, gtm-dashboard.md)
- 🔴 No innovation queue
- 🔴 Experiments timing out (0/5 kept)
- 🔴 No worktree boundary guard

## Phase 1: Foundation (This Week)

### 1.1 Fix Experiment Timeout (Critical)
**Problem:** All experiments timeout at 480s, 0 kept
**Root cause:** Unknown — need to investigate
**Tasks:**
- [ ] Check executor model assignment (MiniMax-M3 vs m2.7-highspeed)
- [ ] Check timeout configuration (300s vs 480s vs 900s)
- [ ] Check if executor actually receives prompt
- [ ] Add timeout debug logging
- [ ] Run manual experiment to isolate

### 1.2 Make GTM Mayor Persistent
**Problem:** Researcher daemon shuts down after research completes
**Fix:** Remove `shutdown-after-completion` from `queue-all-research`
**Tasks:**
- [ ] Modify `gptel-auto-workflow-queue-all-research` in `gptel-auto-workflow-projects.el`
- [ ] Add evolution timer to researcher daemon (like auto-workflow has 3600s)
- [ ] Ensure researcher daemon stays alive between pipeline runs

### 1.3 Rename Daemons
**Current:** `ov5-auto-workflow`, `ov5-researcher`
**Target:** `ov5-pmf-mayor`, `ov5-gtm-mayor`
**Tasks:**
- [ ] Update `scripts/run-auto-workflow-cron.sh` daemon names
- [ ] Update `scripts/run-pipeline.sh` references
- [ ] Update `scripts/watchdog-daemon.sh`
- [ ] Update crontab generation in `scripts/install-cron.sh`
- [ ] Update `mementum/state.md` references

## Phase 2: Dashboards (Next Week)

### 2.1 PMF Dashboard
**File:** `var/tmp/product-dashboard.md`
**Content:**
- Current PLG step (1-5)
- Experiments today/this week
- Keep-rate trend
- Growth metrics
- Competitive gap closures
- Cost per experiment
- Backend performance

**Tasks:**
- [ ] Create `gptel-auto-workflow--update-product-dashboard` function
- [ ] Call on every experiment completion
- [ ] Format: timestamp, one-line resume, blockers, in-flight

### 2.2 GTM Dashboard
**File:** `var/tmp/gtm-dashboard.md`
**Content:**
- Current JTBD step (1-5)
- Research findings this week
- Unmet outcomes ranked
- Segment opportunities
- Strategic recommendations
- Human decisions needed

**Tasks:**
- [ ] Create `gptel-auto-workflow--update-gtm-dashboard` function
- [ ] Call on every research cycle
- [ ] Format: 30-second re-orientation

## Phase 3: Innovation Queue (Week 3)

### 3.1 Create Innovation Queue
**File:** `mementum/innovation-queue.md`
**Format:**
```markdown
## Queue

| ID | Source | Technique | Expected Impact | Status | Experiment ID |
|----|--------|-----------|-----------------|--------|---------------|
| 1 | GTM: GitHub trends | Hashline editing | +15% keep-rate | validated | exp-2026-06-03-1 |
| 2 | GTM: arXiv paper | Context compression | -30% tokens | pending | - |
```

**Tasks:**
- [ ] Create `mementum/innovation-queue.md` template
- [ ] Add `gptel-auto-workflow--innovation-queue-add` (GTM)
- [ ] Add `gptel-auto-workflow--innovation-queue-update` (PMF)
- [ ] Add `gptel-auto-workflow--innovation-queue-list` (both)

## Phase 4: Worktree Safety (Week 4)

### 4.1 Boundary Verification
**Problem:** Edit tools can leak into mayor checkout
**Fix:** Verify worktree before EVERY edit
**Tasks:**
- [ ] Add to executor prompt: "Before EVERY edit, run: git -C <worktree> rev-parse --show-toplevel"
- [ ] Add post-edit check: verify file landed in worktree, not mayor checkout
- [ ] Add `git stash` ban to executor prompt

### 4.2 Mayor Commit Guard
**Problem:** Bypassed edit guard can contaminate mayor checkout
**Fix:** Pre-commit hook in mayor checkout
**Tasks:**
- [ ] Create `.git/hooks/pre-commit` in mayor checkout
- [ ] Refuse commits touching worker-owned surfaces
- [ ] Document in `scripts/setup-ov5-cowork.sh`

## Phase 5: Cross-Mayor Communication (Month 2)

### 5.1 Bead Protocol
**GTM → PMF:**
```markdown
---
id: gtm-2026-06-03-1
source: GitHub trend
technique: Hashline editing
expected-impact: +15% keep-rate
priority: high
---
```

**PMF → GTM:**
```markdown
---
id: pmf-2026-06-03-1
experiment: exp-2026-06-03-1
result: kept
score: 8/9
actual-impact: +12% keep-rate
---
```

**Tasks:**
- [x] Define bead schema for cross-mayor communication
- [x] Create parser in `gptel-auto-workflow-beads.el`
- [x] Auto-file beads from research findings
- [x] Auto-update beads from experiment results

### 5.2 Human Decision Gate
**Between GTM and PMF:**
- GTM proposes: "Market needs X"
- Human decides: "Focus on X"
- PMF executes: "Running experiments on X..."

**Tasks:**
- [x] Add `mementum/decisions/` directory
- [x] Create decision template with options + trade-offs
- [x] Surface in both dashboards
- [x] Block PMF dispatch until human decides (configurable)

## Phase 6: Full Separation (Month 3)

### 6.1 Move Strategy to GTM
**Current:** Auto-workflow handles ontology evolution
**Target:** GTM Mayor owns strategy/ontology
**Tasks:**
- [x] Move `gptel-auto-workflow-ontology-router.el` evolution to researcher
- [x] Move strategy generation to researcher
- [x] PMF Mayor reads strategy from `mementum/gtm/strategy-roadmap.md`

### 6.2 Codify Commands
**Current:** Inline cron loops in `run-pipeline.sh`
**Target:** Standalone commands like Mayor Method
**Tasks:**
- [x] Create `assistant/commands/pmf-mayor-*.md`
- [x] Create `assistant/commands/gtm-mayor-*.md`
- [x] Single invocation per loop body (via emacsclient)

## Phase 7: Metrics & Evolution (Ongoing)

### 7.1 Innovation Metrics
| Metric | PMF | GTM |
|--------|-----|-----|
| Experiment velocity | experiments/day | - |
| Keep-rate | % experiments kept | - |
| Time to validate | hours per experiment | - |
| Market insight velocity | - | findings/day |
| Strategy accuracy | - | % validated predictions |
| PMF signal strength | - | correlation: insight → keep |

**Tasks:**
- [x] `gptel-auto-workflow--pmf-metrics` — experiments/day, keep-rate %, hours/validation
- [x] `gptel-auto-workflow--gtm-metrics` — findings/day, strategy accuracy %, PMF signal
- [x] Dashboard templates updated with metric placeholders
- [x] Auto-update on experiment/research completion

### 7.2 Self-Evolution
- PMF Mayor evolves: skill graph, backend routing, experiment prompts
- GTM Mayor evolves: research strategies, market models, JTBD definitions
- Both feed: AutoTTS traces → unified evolution

## Dependencies

```
Phase 1 (Foundation)
  ├── 1.1 Fix timeout
  └── 1.2 Make persistent
        └── Phase 2 (Dashboards)
              └── Phase 3 (Queue)
                    └── Phase 4 (Safety)
                          └── Phase 5 (Communication)
                                └── Phase 6 (Separation)
                                      └── Phase 7 (Metrics)
```

## Next Action

**Start Phase 1.1:** Investigate why experiments timeout.

Run: Check executor model assignment and timeout configuration.
