# Auto-Workflow

> Semi-autonomous overnight optimization with morning review.

## Implementation Status

| Component | Status | Automation |
|-----------|--------|------------|
| Nightly branch creation | ✓ Implemented | Automatic |
| Agent optimization | ✓ Implemented | Automatic |
| Benchmark runner | ✓ Implemented | Automatic |
| Auto-commit on pass | ✓ Implemented | Automatic |
| Retry on failure | ✓ Implemented | Automatic (1 retry) |
| Metrics collection | ✓ Implemented | Automatic (JSON) |
| Morning summary | ✓ Implemented | Automatic (markdown) |
| Cron scheduling | ✓ Implemented | Automatic (2 AM daily) |
| Human review | ✓ Implemented | Morning cherry-pick/reject |

**Entry point:** `gptel-auto-workflow-run` in `gptel-tools-agent.el`

## Semi-Autonomous Flow

```
Human (once)           Agent (overnight)              Human (morning)
    │                        │                              │
    ├─ Set objectives ──────►│                              │
    │   (gptel-auto-         ├─ Create nightly branch       │
    │    workflow-targets)   ├─ For each target:            │
    │                        │  ├─ Run agent                 │
    │                        │  ├─ Run tests                 │
    │                        │  ├─ Pass → commit             │
    │                        │  └─ Fail → retry once         │
    │                        ├─ Generate summary             │
    │                        └─ Return to main               │
    │                                                       │
    │◄─────────────────────────────────────────────────────►│
                      Morning review                         │
                    (cherry-pick or reject)                  │
```

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

**Document Version:** 1.1  
**Last Updated:** 2026-03-23  
**Changes:** Added Scheduled Runs (Cron) section