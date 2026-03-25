# Auto-Workflow

> Autonomous Research Agent with LLM brain and human eyes/hands.

## Philosophy

```
LLM = Brain (decides, judges, reasons)
We  = Eyes (gather context) + Hands (execute)
Never ask user. Try harder, again and again.
Never touch main. All changes wait in staging.
```

## Implementation Status

| Layer | Component | Status |
|-------|-----------|--------|
| **Brain** | LLM target selection | ✓ |
| **Brain** | LLM quality grading | ✓ |
| **Brain** | LLM keep/discard | ✓ |
| **Eyes** | Context gathering | ✓ |
| **Hands** | Tests before push | ✓ |
| **Hands** | optimize/* branches | ✓ |
| **Hands** | Staging verification | ✓ |
| **Autonomy** | Retry on failure | ✓ |

## Entry Points

```elisp
;; Cron: 2 AM daily (recommended)
crontab cron.d/auto-workflow

;; Manual run
M-x gptel-auto-workflow-run-sync
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    AUTO-WORKFLOW                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. SYNC staging from main                               │
│     └─→ staging = main (never touches project root)      │
│                                                          │
│  2. EYES gather context                                  │
│     └─→ Git history, file sizes, TODOs                  │
│                                                          │
│  3. BRAIN decides targets (LLM)                          │
│     └─→ Which files to optimize                          │
│                                                          │
│  4. HANDS execute in worktree                            │
│     └─→ Create optimize/* branch                         │
│     └─→ Executor makes changes                           │
│     └─→ Run tests + nucleus validation                   │
│                                                          │
│  5. BRAIN validates (LLM)                                │
│     └─→ Grader (6/6 pass)                                │
│     └─→ Comparator (keep/discard)                        │
│                                                          │
│  6. MERGE to staging                                     │
│     └─→ Auto-resolve conflicts (--theirs)                │
│     └─→ Verify staging in isolated worktree               │
│                                                          │
│  7. PUSH staging to origin                               │
│     └─→ Human reviews                                    │
│     └─→ Human merges to main                             │
│                                                          │
└─────────────────────────────────────────────────────────┘

IMPORTANT: Auto-workflow NEVER touches main branch.
All merges wait in staging for human review.
```

## Staging Branch Protection

### Why Staging?

| Problem | Solution |
|---------|----------|
| Main could break | Tests run on staging first |
| Bad merge affects main | Staging isolation |
| Human must verify | Human merges staging → main |
| Integration issues | Full tests on merged result |

### Flow

```
main ─────────────────────────────────────────────► main
  │                                                  ▲
  │ 1. sync                                          │ 6. human merge
  ▼                                                  │
staging ◄──── 2. merge ──── optimize/* ◄── executor ◄─┘
  │
  │ 3. verify (tests + nucleus)
  │
  │ 4. push to origin
  │
  └─► Human reviews and merges to main
```

### Human Workflow

```bash
# Morning: check what's in staging
git log staging..main --oneline

# Verify staging
git checkout staging
./scripts/run-tests.sh

# If good: merge to main
git checkout main
git merge staging
git push origin main

# If bad: reset staging
git checkout staging
git reset --hard main
git push --force origin staging
```

## Target Selection

**LLM decides**, we don't second-guess.

```elisp
(gptel-auto-workflow-select-targets callback)
;; 1. Gather context: git history, file sizes, TODOs
;; 2. Ask analyzer LLM: "Select 3 files to optimize"
;; 3. Execute LLM's decision
```

## Safety Pipeline

```
Executor makes changes
       ↓
   Grader validates (LLM)
       ↓
   Tests run
       ↓
   Nucleus validation
       ↓
   Comparator decides (LLM)
       ↓
   Push to optimize/* only
```

## program.md

Human-editable objectives at `docs/auto-workflow-program.md`.

**Note**: LLM decides targets. Static targets are fallback only.

## Skills

### Target Skills

`mementum/knowledge/optimization-skills/{target}.md`

Track successful/failed mutations per target.

### Mutation Skills

`mementum/knowledge/mutations/{type}.md`

Reusable hypothesis templates.

## Pipeline

```
1. Analyze (LLM)   → Detect patterns, suggest hypotheses
2. Implement       → Executor makes changes in optimize/* worktree
3. Grade (LLM)     → Validate quality (6/6 pass)
4. Test            → Run tests + nucleus validation
5. Decide (LLM)    → Compare before/after, keep/discard
6. Commit          → Commit to optimize/* branch
7. Merge           → optimize/* → staging (auto-resolve conflicts)
8. Verify          → Test staging in isolated worktree
9. Push            → staging to origin (NEVER main)
10. Human review   → Human merges staging → main
```

### Staging Verification

After executor commits to optimize/*:

1. **Merge to staging** - Auto-resolve conflicts with `--theirs`
2. **Create staging worktree** - Isolated from project root
3. **Run tests** - `scripts/run-tests.sh`
4. **Run nucleus** - `scripts/verify-nucleus.sh`
5. **Push staging** - To origin for human review
6. **Human merges** - staging → main manually

### Decision

**LLM decides** based on:
- Eight Keys score
- Code quality (docstring coverage)
- Combined improvement

**Local fallback** only if LLM unavailable.

## TSV Format

```
experiment_id  target  hypothesis  score_before  score_after  decision
001            retry   add caching  0.72         0.78         kept
002            retry   simplify     0.78         0.75         discarded
```

## Stop Condition

Stops when:
- Max experiments reached (default: 10 per target)
- 3 consecutive experiments with no improvement
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
# 2 AM daily (use -sync version for cron)
emacsclient -e '(gptel-auto-workflow-run-sync)'
```

**Important:** Use `gptel-auto-workflow-run-sync` (not `-run`) for cron. The sync version blocks until all experiments complete, keeping the event loop alive with `accept-process-output`.

### Manual

```elisp
M-x gptel-auto-workflow-run-sync

;; Or programmatically
(gptel-auto-workflow-run-sync '("gptel-ext-retry.el"))
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
| `gptel-auto-workflow-run-sync` | Main entry for cron (~32 experiments/night), blocks until complete |
| `gptel-auto-workflow-run` | Async entry for interactive use |
| `gptel-auto-experiment-loop` | Per-target experiment loop with dynamic stop |
| `gptel-auto-experiment-run` | Single experiment with full subagent pipeline |
| `gptel-auto-experiment-analyze` | Pattern detection from previous experiments |
| `gptel-auto-experiment-grade` | Validate experiment quality (LLM threshold) |
| `gptel-auto-experiment-decide` | Compare before/after, decide keep/discard (50% grader + 50% quality) |
| `gptel-auto-experiment-should-stop-p` | Check stop condition (no-improvement threshold) |
| `gptel-auto-experiment--extract-hypothesis` | Parse hypothesis from output (multiple patterns) |
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

## Multi-Machine Workflow

When multiple machines run auto-evolution on the same targets, branch conflicts are prevented by including the hostname in the branch name.

### Branch Format

```
optimize/{target}-{hostname}-exp{N}
```

**Examples:**

| Machine | Target | Branch |
|---------|--------|--------|
| `pi5.local` | gptel-ext-retry.el | `optimize/retry-pi5.local-exp1` |
| `debian.local` | gptel-ext-retry.el | `optimize/retry-debian.local-exp1` |
| `pi5.local` | gptel-ext-context.el | `optimize/context-pi5.local-exp1` |

### Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `gptel-auto-experiment-auto-push` | `t` | Auto-push to origin after commit |

### Workflow

1. **Machine runs experiment** → Creates branch with hostname
2. **Commit succeeds** → Branch pushed to origin (Forgejo)
3. **Morning review** → Human reviews and merges via PR

### Merge Process (Forgejo)

```bash
# Fetch all branches
git fetch origin

# List optimize branches from all machines
git branch -r 'origin/optimize/*'

# Review specific branch
git log main..origin/optimize/retry-pi5.local-exp1

# Squash merge to main
git checkout main
git merge --squash origin/optimize/retry-pi5.local-exp1
git commit -m "◈ Optimize retry: {hypothesis summary}"
git push origin main

# Delete experiment branch
git push origin --delete optimize/retry-pi5.local-exp1
```

### PR Workflow

On Forgejo web UI:
1. Navigate to **Pull Requests** → **New Pull Request**
2. Select branch: `optimize/retry-pi5.local-exp1` → `main`
3. Review changes, approve, merge
4. Delete branch after merge

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
0 2 * * * emacsclient -e '(gptel-auto-workflow-run-sync)'
```

### Custom Schedules

Edit `cron.d/auto-workflow` to customize:

```cron
# Every night at 2:30 AM
30 2 * * * emacsclient -e '(gptel-auto-workflow-run-sync)'

# Every Sunday at 3 AM (weekly instead of daily)
0 3 * * 0 emacsclient -e '(gptel-auto-workflow-run-sync)'

# Every 6 hours
0 */6 * * * emacsclient -e '(gptel-auto-workflow-run-sync)'
```

### Specific Targets at Different Times

```cron
# Run specific targets at staggered times
0 2 * * * emacsclient -e '(gptel-auto-workflow-run-sync (quote ("gptel-ext-retry.el")))'
30 2 * * * emacsclient -e '(gptel-auto-workflow-run-sync (quote ("gptel-ext-context.el")))'
0 3 * * * emacsclient -e '(gptel-auto-workflow-run-sync (quote ("gptel-tools-code.el")))'
```

### Prerequisites

1. **Emacs daemon must be running:**
   ```bash
   emacs --daemon
   ```

2. **Or start daemon in cron:**
   ```cron
   @reboot emacs --daemon
   0 2 * * * emacsclient -e '(gptel-auto-workflow-run-sync)'
   ```

**Note:** Always use `gptel-auto-workflow-run-sync` for cron. The `-sync` version uses `accept-process-output` to keep the event loop alive until experiments complete.

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
M-x gptel-auto-workflow-run-sync

;; From shell
emacsclient -e '(gptel-auto-workflow-run-sync)'
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
| Daily 2:00 AM | `gptel-auto-workflow-run-sync` | Overnight optimization experiments |
| Weekly Sun 4:00 AM | `gptel-mementum-weekly-job` | Synthesis + decay |
| Weekly Sun 5:00 AM | `gptel-benchmark-instincts-weekly-job` | Evolution batch commit |

Logs: `var/tmp/cron/*.log`

### Cron Integration

```cron
# Weekly: instincts evolution + mementum optimization
0 3 * * 0 emacsclient -e '(gptel-benchmark-instincts-weekly-job)'
```

---

**Document Version:** 1.7  
**Last Updated:** 2026-03-25  
**Release:** v2026.03.25  
**Changes:** Updated for sync version (cron compatibility), 50/50 comparator weights, relaxed grader criteria