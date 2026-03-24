# Auto-Workflow

> Autonomous Research Agent with continuity + compounding.

## Implementation Status

| Layer | Component | Status |
|-------|-----------|--------|
| **Objectives** | program.md (human-editable) | ✓ |
| **Continuity** | mementum memories | ✓ |
| **Compounding** | optimization skills | ✓ |
| **Mutations** | mutation skills | ✓ |
| **Engine** | ~32 experiments/night | ✓ |
| **Validation** | analyzer/grader/comparator | ✓ |
| **Maintenance** | mementum weekly optimization | ✓ |

## Entry Points

```elisp
;; Autonomous Research Agent (recommended)
M-x gptel-auto-workflow-run-autonomous

;; Legacy (uses elisp variable)
M-x gptel-auto-workflow-run
```

## Architecture

```
docs/auto-workflow-program.md     ← Human edits objectives
            │
            ▼
┌─────────────────────────────────────────────────────────┐
│              gptel-auto-workflow-run-autonomous         │
│                                                         │
│  1. orient()    → load program.md + skills             │
│  2. experiments → ~32/night with skill guidance         │
│  3. metabolize() → synthesize to mementum              │
└─────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────┐
│                    mementum/                            │
│                                                         │
│  memories/auto-workflow-{date}.md    (continuity)       │
│  knowledge/optimization-skills/      (compounding)      │
│  knowledge/mutations/               (reusable patterns) │
└─────────────────────────────────────────────────────────┘
```

## program.md

Human-editable objectives at `docs/auto-workflow-program.md`:

```markdown
## Targets
lisp/modules/gptel-ext-retry.el
lisp/modules/gptel-ext-context.el

## Constraints
### Immutable Files
early-init.el
lisp/eca-security.el

## Mutation Strategy
- [x] caching
- [x] lazy-initialization
- [x] simplification
```

## Skills

### Target Skills

`mementum/knowledge/optimization-skills/{target}.md`

Track successful/failed mutations per target:

```yaml
---
title: Optimization Skill: retry
phi: 0.85
runs: 3
---

## Successful Mutations
| Mutation | Success Rate | Avg Delta |
|----------|-------------|-----------|
| caching  | 3/3         | +0.06     |

## Nightly History
| Date       | Kept | Score Δ |
|------------|------|---------|
| 2026-03-22 | 3    | +0.12   |
```

### Mutation Skills

`mementum/knowledge/mutations/{type}.md`

Reusable hypothesis templates:

```yaml
---
title: Mutation Skill: caching
phi: 0.75
---

## Hypothesis Templates
"Add caching to {component} to reduce redundant {operation}"

## When to Apply
- Repeated lookups detected
- Same computation called multiple times

## Success History
| Target | Date | Delta |
|--------|------|-------|
| retry  | 2026-03-22 | +0.06 |
```

## Subagent Pipeline

Each experiment goes through:

| Stage | Subagent | Purpose |
|-------|----------|---------|
| 1. Analyze | `analyzer` | Detect patterns from previous experiments, suggest hypotheses |
| 2. Implement | `code` (executor) | Run agent with guided prompt (reads git history + analyzer output) |
| 3. Validate | `grader` | Check hypothesis clarity, minimal changes. LLM decides if quality sufficient |
| 4. Benchmark | — | Run verify-nucleus.sh + Eight Keys scoring |
| 5. Decide | `comparator` | Compare before/after (includes code quality) |

### Code Quality Integration

Code quality (docstring coverage) is calculated before the decide stage and passed to the comparator:

```elisp
;; In gptel-auto-experiment-run:
(let ((code-quality (or (gptel-auto-experiment--code-quality-score) 0.5)))
  (gptel-auto-experiment-decide
   (list :score baseline :code-quality 0.5)
   (list :score score-after :code-quality code-quality)
   callback))
```

### Decision Logic

**With comparator subagent:** The comparator receives both `:score` and `:code-quality` values and makes a blind A/B decision based on quality, completeness, and correctness.

**Fallback (no subagent):** Uses combined score:

```
combined = 70% * grader_score + 30% * code_quality_score
```

This rewards improvements that:
- Pass grader validation (hypothesis, minimal changes)
- Improve code quality (docstrings, clarity)

### Code Quality Scoring

```elisp
(gptel-benchmark--code-quality-score code)
;; => 0.0-1.0 (docstring coverage)
```

- 1.0 = all functions have docstrings
- 0.5 = half of functions have docstrings
- 0.0 = no functions have docstrings

### LLM Degradation Detection

```elisp
(gptel-benchmark--detect-llm-degradation response expected-keywords)
;; => (:degraded-p t :reason "I apologize" :score 0.67)
```

Detects:
- Forbidden keywords (apologies, AI self-reference)
- Off-topic responses (missing expected keywords)

## TSV Format (Explainable Results)

```
experiment_id  target  hypothesis  score_before  score_after  code_quality  delta  decision  duration  grader_quality  grader_reason  comparator_reason  analyzer_patterns
001            retry   add caching  0.72         0.78         0.85          +0.06  kept      842       85              "Hypothesis clear"  "KEEP - improvement"  "caching pattern"
002            retry   simplify err 0.78         0.75         0.50          -0.03  discarded 603       70              "Larger than ideal"  "DISCARD - regression"  "simplification (1/2)"
003            retry   lazy init    0.78         0.81         1.00          +0.03  kept      915       90              "Excellent hypothesis"  "KEEP - better performance"  "caching (3/3), lazy-init"
```

## Dynamic Stop Condition

The experiment loop stops when:
- Max experiments reached (`gptel-auto-experiment-max-per-target`), OR
- `gptel-auto-experiment-no-improvement-threshold` consecutive experiments show no improvement

This prevents wasting time when:
- The optimization space is exhausted
- The analyzer detects pattern exhaustion
- Scores plateau

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `gptel-auto-experiment-time-budget` | 600s | Max time per experiment |
| `gptel-auto-experiment-grade-timeout` | 60s | Timeout for grading subagent |
| `gptel-auto-experiment-max-per-target` | 10 | Max experiments per file |
| `gptel-auto-experiment-no-improvement-threshold` | 3 | Stop after N no-improvements |
| `gptel-auto-experiment-use-subagents` | t | Use analyzer/grader/comparator |

## Usage

### Cron (Scheduled)

```bash
# 2 AM daily
emacsclient -e '(gptel-auto-workflow-run)'
```

### Manual

```elisp
M-x gptel-auto-workflow-run

;; Or programmatically
(gptel-auto-workflow-run '("gptel-ext-retry.el"))
```

### Morning Review

```bash
# View results
cat var/tmp/experiments/$(date +%Y-%m-%d)/results.tsv | column -t -s $'\t'

# Review branches
git branch --list 'optimize/*'

# Merge successful experiments
git checkout main && git merge optimize/retry-exp3

# Or cherry-pick specific commits
git cherry-pick <sha>
```

## Key Functions

| Function | Purpose |
|----------|---------|
| `gptel-auto-workflow-run` | Main entry (~32 experiments/night) |
| `gptel-auto-experiment-loop` | Per-target experiment loop with dynamic stop |
| `gptel-auto-experiment-run` | Single experiment with full subagent pipeline |
| `gptel-auto-experiment-analyze` | Pattern detection from previous experiments |
| `gptel-auto-experiment-grade` | Validate experiment quality (LLM threshold) |
| `gptel-auto-experiment-decide` | Compare before/after, decide keep/discard (70% grader + 30% quality) |
| `gptel-auto-experiment-should-stop-p` | Check stop condition (no-improvement threshold) |
| `gptel-auto-experiment--extract-hypothesis` | Parse hypothesis from output |
| `gptel-auto-experiment--summarize` | Truncate hypothesis to 6 words |
| `gptel-auto-experiment--code-quality-score` | Calculate docstring coverage |
| `gptel-auto-experiment-log-tsv` | Log with explainable columns |
| `gptel-auto-workflow-metabolize` | Synthesize results, update skills |
| `gptel-auto-workflow-update-target-skill` | Update target skill after experiment |
| `gptel-auto-workflow-update-mutation-skill` | Update mutation skill after experiment |

### Subagent Functions

| Function | Purpose |
|----------|---------|
| `gptel-benchmark-grade` | Grade output against expected/forbidden behaviors |
| `gptel-benchmark-analyze` | Detect patterns, issues, recommendations |
| `gptel-benchmark-compare` | A/B comparison with winner/reasoning |
| `gptel-benchmark-execute` | Apply changes to target |
| `gptel-benchmark-review` | Review code quality |
| `gptel-benchmark-explore` | Explore codebase |

### Quality Functions

| Function | Purpose |
|----------|---------|
| `gptel-benchmark--code-quality-score` | Score docstring coverage (0.0-1.0) — internal |
| `gptel-benchmark--detect-llm-degradation` | Detect off-topic/repetition/loops — internal |
| `gptel-auto-experiment--code-quality-score` | Wrapper for experiment workflow |

Note: Functions with `--` (double dash) are internal. Use the wrapper for experiment integration.

### Mementum Functions

| Function | Purpose |
|----------|---------|
| `gptel-mementum-build-index` | Build recall index for O(1) lookup |
| `gptel-mementum-recall` | Quick topic lookup |
| `gptel-mementum-decay-skills` | Decay stale skills (weekly) |
| `gptel-mementum-weekly-job` | Weekly maintenance orchestration |

---

## Overview

6-phase workflow for autonomous optimization with self-improvement:

1. **Frame** — Define target, goal, constraints
2. **Research** — Understand, benchmark baseline
3. **Design** — Propose minimal approach
4. **Execute** — Implement in worktree, validate
5. **Review** — Summary, recommendation
6. **Learn** — Auto-evolve via 相生/相克

## Directory

All experiment files go to `var/tmp/experiments/`:

```
var/tmp/experiments/
├── {run-id}/                    # e.g., 2026-03-24
│   ├── {target}/                # e.g., retry
│   │   ├── frame.md             # Phase 1 output
│   │   ├── research.md          # Phase 2 output
│   │   ├── design.md            # Phase 3 output
│   │   ├── summary.md           # Phase 5 output
│   │   └── metrics.json         # Phase 6 metrics
│   └── worktrees/
│       ├── 001/                 # experiment-001 worktree
│       └── 002/                 # experiment-002 worktree
```

---

## Usage

### Programmatic (Recommended)

```elisp
;; Run with default targets
(gptel-auto-workflow-run)

;; Run with specific targets
(gptel-auto-workflow-run '("gptel-ext-retry.el" "gptel-ext-context.el"))

;; Configure targets
(setq gptel-auto-workflow-targets
      '("gptel-ext-retry.el" "gptel-ext-context.el" "gptel-tools-code.el"))
```

### Interactive

```elisp
M-x gptel-auto-workflow-run
```

### Cron (Scheduled)

```bash
# Install cron jobs (runs at 2 AM daily)
crontab cron.d/auto-workflow

# Manual trigger
emacsclient -e '(gptel-auto-workflow-run)'
```

---

## Available Functions

| Function | Purpose |
|----------|---------|
| `gptel-auto-workflow-run` | Main entry point (orchestrates all phases) |
| `gptel-auto-workflow-create-worktree` | Create isolated git worktree |
| `gptel-auto-workflow-delete-worktree` | Delete experiment worktree |
| `gptel-auto-workflow-cleanup-run` | Clean up all worktrees for a run |
| `gptel-auto-workflow-benchmark` | Run tests and measure time |
| `gptel-auto-workflow-save-metrics` | Save metrics to JSON |
| `gptel-auto-workflow-generate-summary` | Generate summary markdown |

---

## Manual Phases

### Single Experiment

```
#=frame #file var/tmp/experiments/{run-id}/{target}/frame.md
#=research #ground #file
#=design #subtract #file
#=code #checklist
#=review #file
#=review #meta #file
```

### Parallel Overnight (via RunAgent)

```
RunAgent("code", "optimize gptel-ext-retry.el following docs/auto-workflow.md")
RunAgent("code", "optimize gptel-ext-context.el following docs/auto-workflow.md")
RunAgent("code", "optimize gptel-tools-code.el following docs/auto-workflow.md")
```

---

## Phase 1: Frame

**Trigger:** `#=frame #file var/tmp/experiments/{run-id}/{target}/frame.md`

**Purpose:** Define the optimization experiment.

**Output:**
```markdown
# Frame: {target}

## Target
- File: lisp/modules/{target}.el
- Lines: ~N lines

## Goal
- Type: speed / memory / clarity
- Target: X% improvement

## Constraints
- Token budget: 5000
- Time budget: 300s (5 min)
- Immutable files:
  - early-init.el, pre-early-init.el
  - lisp/eca-security.el
  - lisp/modules/gptel-ext-security.el
  - lisp/modules/gptel-ext-tool-confirm.el
  - lisp/modules/gptel-ext-tool-permits.el
  - lisp/modules/gptel-sandbox.el
  - eca/**
  - mementum/**
  - assistant/**
  - var/elpa/**

## Success Criteria
- Tests pass: ./scripts/verify-nucleus.sh
- Benchmark improvement: ≥5%
```

---

## Phase 2: Research

**Trigger:** `#=research #ground #file`

**Purpose:** Understand current code and establish baseline.

**Actions:**
1. Read target file
2. Run benchmark (baseline)
3. Identify optimization opportunities
4. Document findings

**Output:** `var/tmp/experiments/{run-id}/{target}/research.md`

```markdown
# Research: {target}

## Current State
- Lines: N
- Key functions: [...]
- Hot paths: [...]

## Benchmark Baseline
| Metric | Value |
|--------|-------|
| Execution time | X.XX s |
| Test count | N/N pass |

## Opportunities (Top 3)
1. **{opportunity-1}** — Expected: X% improvement
2. **{opportunity-2}** — Expected: Y% improvement
3. **{opportunity-3}** — Expected: Z% improvement

## Risks
- {risk-1}
- {risk-2}
```

---

## Phase 3: Design

**Trigger:** `#=design #subtract #file`

**Purpose:** Propose minimal optimization approach.

**Actions:**
1. Select best opportunity
2. Design minimal change
3. Estimate improvement
4. Identify risks and mitigations

**Output:** `var/tmp/experiments/{run-id}/{target}/design.md`

```markdown
# Design: {target}

## Approach
{chosen approach — minimal, targeted}

## Changes
1. **{change-1}**
   - Before: {code}
   - After: {code}
   - Reason: {why}

2. **{change-2}**
   ...

## Estimated Improvement
- Time: X% faster
- Risk: {low/medium/high}

## Implementation Steps
1. {step-1}
2. {step-2}
3. {step-3}
```

---

## Phase 4: Execute

**Trigger:** `#=code #checklist`

**Purpose:** Implement optimization in isolated worktree.

**Actions:**
1. Create git worktree
2. Switch to worktree
3. Implement changes
4. Run tests
5. Run benchmark
6. Compare results

**Checklist:**
```
- [ ] Worktree created: git worktree add -b experiment-N var/tmp/experiments/{run-id}/worktrees/N
- [ ] Changes implemented
- [ ] Tests pass: ./scripts/verify-nucleum.sh
- [ ] Benchmark after
- [ ] Improvement confirmed
- [ ] Ready for review
```

**Git Commands:**
```bash
# Create worktree
git worktree add -b experiment-{N} var/tmp/experiments/{run-id}/worktrees/{N} main

# In worktree, after successful experiment
git add -A
git commit -m "experiment-{N}: optimize {target} (+X%)"

# If failed, discard
git checkout main
git branch -D experiment-{N}
```

---

## Phase 5: Review

**Trigger:** `#=review #file`

**Purpose:** Summarize results and recommend action.

**Output:** `var/tmp/experiments/{run-id}/{target}/summary.md`

```markdown
# Summary: {target}

## Results

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Time   | X.XX s | Y.YY s | -Z% |
| Tests  | N/N    | N/N   | ✓    |

## Changes
- {change-1}
- {change-2}

## Recommendation
- [ ] ★★★ MERGE — Ready to merge
- [ ] ★★☆ REVIEW — Needs human review
- [ ] ★☆☆ REJECT — Discard

## Commands
# Cherry-pick
git cherry-pick experiment-{N}

# Or review diff
git diff main..experiment-{N}
```

---

## Phase 6: Learn

**Trigger:** `#=review #meta #file`

**Purpose:** Auto-evolve the workflow via 相生/相克.

**Actions:**
1. Record metrics
2. Detect anti-patterns (相克)
3. Generate improvements (相生)
4. Update workflow document
5. Store learning to mementum

**Output:** `var/tmp/experiments/{run-id}/{target}/metrics.json`

```json
{
  "run_id": "2026-03-24",
  "target": "gptel-ext-retry.el",
  "completed": true,
  "tests_passed": true,
  "improvement_pct": 28,
  "tokens_used": 4200,
  "time_seconds": 240,
  "merged": false
}
```

### Anti-Pattern Detection (相克)

| Anti-Pattern | Element | Detection | Remedy |
|--------------|---------|-----------|--------|
| Aborted | Wood | `completed: false` | Reduce scope, better framing |
| Test failure | Earth | `tests_passed: false` | Add validation steps |
| No improvement | Fire | `improvement_pct < 5` | Better research phase |
| Budget exceeded | Metal | `tokens_used > budget` | Stricter constraints |
| Bad framing | Water | Unclear target | Improve frame template |

### Improvement Generation (相生)

```
Water → Wood: Better framing → Better execution
Wood → Fire: Better execution → Better insights
Fire → Earth: Better insights → Better validation
Earth → Metal: Better validation → Better coordination
Metal → Water: Better coordination → Better framing
```

### Store Learning

```bash
# If significant insight discovered
# Create mementum/memories/{slug}.md
# Commit: 💡 auto-workflow: {insight}
```

---

## Morning Review

```bash
# List experiments
ls var/tmp/experiments/

# Check summaries
cat var/tmp/experiments/2026-03-24/*/summary.md

# Review specific experiment
git diff main..experiment-001

# Cherry-pick good ones
git cherry-pick experiment-001 experiment-003

# Cleanup worktrees
git worktree prune

# Delete experiment branches
git branch -D $(git branch --list 'experiment-*')
```

---

## Optimization Targets (Priority)

| Priority | Target | Focus | Expected |
|----------|--------|-------|----------|
| 1 | `gptel-ext-retry.el` | Memoization, reduce plist-get | 20-40% |
| 2 | `gptel-ext-context.el` | Optimize compaction | 15-30% |
| 3 | `gptel-tools-code.el` | Cache results | 25-50% |
| 4 | `nucleus-presets.el` | Reduce switching overhead | 10-20% |
| 5 | `gptel-ext-tool-confirm.el` | Optimize UI | 10-15% |

---

## Safety Mechanisms

| Layer | Mechanism | Enforcement |
|-------|-----------|-------------|
| **Isolation** | Git worktree | Each experiment isolated |
| **Tests** | `verify-nucleus.sh` | MUST pass before commit |
| **Benchmark** | Workflow benchmark | MUST show improvement |
| **Budget** | Token/time limits | Stop when exceeded |
| **Immutable** | File list | Cannot modify security/core files |
| **Recovery** | Git | Can always revert |

---

## Scheduled Runs (Cron)

### Install Cron Job

```bash
# Install the provided cron configuration
crontab cron.d/auto-workflow

# Or manually add to your crontab
crontab -e
# Add: 0 2 * * * emacsclient -e '(gptel-auto-workflow-run)'
```

### Default Schedule

The default cron job runs nightly at 2 AM:

```
0 2 * * * emacsclient -e '(gptel-auto-workflow-run)'
```

### Custom Schedules

Edit `cron.d/auto-workflow` to customize:

```cron
# Every night at 2:30 AM
30 2 * * * emacsclient -e '(gptel-auto-workflow-run)'

# Every Sunday at 3 AM (weekly instead of daily)
0 3 * * 0 emacsclient -e '(gptel-auto-workflow-run)'

# Every 6 hours
0 */6 * * * emacsclient -e '(gptel-auto-workflow-run)'
```

### Specific Targets at Different Times

```cron
# Run specific targets at staggered times
0 2 * * * emacsclient -e '(gptel-auto-workflow-run (quote ("gptel-ext-retry.el")))'
30 2 * * * emacsclient -e '(gptel-auto-workflow-run (quote ("gptel-ext-context.el")))'
0 3 * * * emacsclient -e '(gptel-auto-workflow-run (quote ("gptel-tools-code.el")))'
```

### Prerequisites

1. **Emacs daemon must be running:**
   ```bash
   emacs --daemon
   ```

2. **Or start daemon in cron:**
   ```cron
   @reboot emacs --daemon
   0 2 * * * emacsclient -e '(gptel-auto-workflow-run)'
   ```

### Logs

Cron output is logged to:

```
var/tmp/cron/auto-workflow.log
```

View logs:
```bash
tail -f var/tmp/cron/auto-workflow.log
```

### Configure Targets

Default targets are defined in `gptel-auto-workflow-targets`:

```elisp
;; In post-early-init.el or init-ai.el
(setq gptel-auto-workflow-targets
      '("gptel-ext-retry.el" 
        "gptel-ext-context.el" 
        "gptel-tools-code.el"))
```

### Manual Trigger

```elisp
;; From Emacs
M-x gptel-auto-workflow-run

;; From shell
emacsclient -e '(gptel-auto-workflow-run)'
```

---

## Integration with Existing Systems

| System | Usage |
|--------|-------|
| `#=frame`, `#=research`, etc. | Existing behaviors |
| `RunAgent` | Parallel execution |
| `gptel-workflow-benchmark.el` | Benchmark validation |
| `gptel-benchmark-auto-improve.el` | 相生/相克 auto-evolution |
| `mementum/` | Store learnings |

---

## Mementum Optimization

Weekly maintenance runs automatically (Sunday 3 AM) via `gptel-benchmark-instincts-weekly-job`:

| Function | Purpose |
|----------|---------|
| `gptel-mementum-build-index` | Build topic → file mapping for O(1) lookup |
| `gptel-mementum-recall` | Quick lookup with git grep fallback |
| `gptel-mementum-decay-skills` | Decay skills not tested in 4+ weeks |
| `gptel-mementum-check-synthesis-candidates` | Detect topics with ≥3 memories |

### Decay Logic

Skills with `last-tested:` older than 4 weeks:
1. **phi decay**: -0.02 per week
2. **Archive**: When phi < 0.3, move to `archive/` subdirectory

### Synthesis Detection

When ≥3 memories share a topic keyword, synthesis loop runs:

1. **Detect** — `gptel-mementum-check-synthesis-candidates` finds topics
2. **Preview** — Show buffer with source memories + proposed content
3. **Approve** — `y-or-n-p` implements human termination gate
4. **Create** — Write `mementum/knowledge/{topic}.md`
5. **Commit** — `💡 synthesis: {topic}`

### Interactive Commands

| Command | Purpose |
|---------|---------|
| `M-x gptel-mementum-synthesis-run` | Run synthesis on all candidates |
| `M-x gptel-mementum-weekly-job` | Full weekly maintenance + synthesis |

### Cron Scheduling

Install scheduled jobs for autonomous operation:

```bash
./scripts/install-cron.sh --dry-run   # Preview
./scripts/install-cron.sh             # Install
```

| Schedule | Function | Purpose |
|----------|----------|---------|
| Daily 2:00 AM | `gptel-auto-workflow-run` | Overnight optimization experiments |
| Weekly Sun 4:00 AM | `gptel-mementum-weekly-job` | Synthesis + decay |
| Weekly Sun 5:00 AM | `gptel-benchmark-instincts-weekly-job` | Evolution batch commit |

Logs: `var/tmp/cron/*.log`

### Cron Integration

```cron
# Weekly: instincts evolution + mementum optimization
0 3 * * 0 emacsclient -e '(gptel-benchmark-instincts-weekly-job)'
```

---

**Document Version:** 1.5  
**Last Updated:** 2026-03-24  
**Release:** v2026.03.24  
**Changes:** Fixed pipeline to 5 stages (code quality integrated into decide), clarified comparator receives code quality, clarified 70/30 is fallback only