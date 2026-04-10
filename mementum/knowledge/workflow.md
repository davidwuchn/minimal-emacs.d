---
title: workflow
status: open
---

Synthesized from 9 memories.

# Auto-Workflow Branching Rule

**Date**: 2026-03-25
**Symbol**: 🔁 pattern

## Rule

```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

## Branch Format

`optimize/{target-name}-{hostname}-exp{N}`

**Example**: `optimize/retry-imacpro.taila8bdd.ts.net-exp1`

## Flow

1. Create worktree with optimize branch
2. Executor makes changes in worktree (isolated from main)
3. If improvement → commit to optimize branch
4. Push to `origin optimize/...` (NOT main!)
5. Human reviews and merges to main via PR

## Why This Matters

- Prevents unreviewed AI changes on main
- Multiple machines can optimize same target without conflicts
- Human gate for quality control

## Code Location

`gptel-tools-agent.el:1134`:
```elisp
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

## Lesson Learned

On 2026-03-25, I mistakenly pushed auto-workflow changes directly to main.
This violated the branching rule. Always check branch before pushing.

# Auto-Workflow E2E Bug: Deleted Buffer

**Discovery:** During e2e test, auto-workflow fails with "Selecting deleted buffer" error.

**Symptoms:**
- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution
- Executor runs for 560s+ without completing changes
- No results logged to TSV file
- Error: `gptel callback error: (error "Selecting deleted buffer")`

**Root Cause:**
The `gptel-auto-workflow--advice-task-override` advice overrides `current-buffer` to return a fixed project buffer. If that buffer is killed during async execution, all callbacks fail.

**Fix Applied:**
1. Added `kill-buffer-query-functions` protection to prevent buffer kill during runs
2. Made `current-buffer` override check liveness each call, fall back if killed
3. Saved original `current-buffer` function before overriding to avoid recursion

**Result:**
- E2E test passed - experiment completed in 230s with `kept` decision
- Score improved: 0.40 → 0.41
- Commit `bae1b73` merged to staging

**Symbol:** ✅ (fixed)

---
title: Auto-Workflow Never Asks
created: 2026-03-25
tags: [auto-workflow, principle, autonomy, resilience]
---

# Auto-Workflow Never Asks User

## The Principle

```
λ autonomous(x).
    fail(x) → retry(x)
    | retry(x) → retry(x)
    | max_retries → log_and_continue
    | ¬ask(user)
    | ¬stop_for_input
```

## What This Means

Auto-workflow is fully autonomous. It never asks the user for:
- Confirmation
- Input
- Decision
- Clarification

Instead, it:
1. Tries again (retry)
2. Tries differently (alternative approach)
3. Logs the failure and continues

## Retry Pattern

```elisp
(defun with-retry (fn max-retries)
  "Call FN, retry on failure, never ask user."
  (let ((attempts 0))
    (while (< attempts max-retries)
      (cl-incf attempts)
      (condition-case err
          (funcall fn)  ; Try
        (error
         (when (< attempts max-retries)
           (sit-for 1)))))))  ; Brief pause, then retry
```

## Examples

| Failure | Don't Do This | Do This |
|---------|---------------|---------|
| Worktree create fails | Ask user "Retry?" | Retry automatically |
| Test fails | Ask "Continue?" | Log and continue to next target |
| LLM timeout | Ask "What now?" | Retry with shorter prompt |
| Push fails | Ask "Force push?" | Retry with fresh auth |

## Why This Matters

- Auto-workflow runs at 2 AM unattended
- No human is watching to answer questions
- Each failure is an opportunity to try again
- Eventual success > immediate failure

## The Rule

**Never use in auto-workflow:**
- `y-or-n-p`
- `yes-or-no-p`
- `read-from-minibuffer`
- `completing-read`
- `user-error` (for recoverable issues)

**Always use instead:**
- Retry logic
- Fallback paths
- Error logging
- Continue to next task

💡 autonomous-workflow-verified-working

## Verification Date: 2026-03-24

## Test Results

| Step | Status | Duration | Details |
|------|--------|----------|---------|
| Worktree creation | ✓ | <1s | optimize/retry-exp1 |
| Executor subagent | ✓ | 80s | Made docstring changes |
| Grader subagent | ✓ | 10s | 6/6 behaviors passed |
| Benchmark | ✓ | 10s | Score 1.0 (no change) |
| Decision | ✓ | <1s | Discarded (no improvement) |
| TSV logging | ✓ | <1s | results.tsv created |

## Full Flow Verified

```
gptel-auto-workflow-run
  → worktree (magit-worktree)
  → executor subagent (gptel-agent--task)
  → grader subagent (LLM, JSON output)
  → benchmark (Eight Keys scoring)
  → comparator (keep/discard)
  → TSV log
```

## Experiment 1 Results

```
target: gptel-ext-retry.el
hypothesis: Adding docstring to improve maintainability
score: 1.00 → 1.00 (no change)
decision: discarded
duration: 100s
grader: 6/6 passed
```

## Analyzer Recommendations

1. Add maintainability-specific metrics
2. Reduce evaluation overhead (100s excessive)
3. Separate scoring tracks: functional vs quality vs docs
4. Weight scores by change category

## Issues Found

1. **API timeouts**: DashScope slow, curl exit 28, retries needed
2. **No score improvement**: Metrics don't capture docstring value
3. **Long duration**: 100s for simple docstring change

## Key Files

- `var/tmp/experiments/2026-03-24/results.tsv` - Experiment log
- `var/tmp/experiments/optimize/retry-exp1/` - Worktree (cleaned up)

## λ autonomous

```
λ workflow. worktree → executor → grader → benchmark → decide → log
λ verified. All steps work, TSV created
λ issue. API timeouts, metrics don't capture docs
```

🔁 evolve-workflow-20260320-154644

workflow/plan-agent: 2 anti-patterns → 2 improvements → 0 capabilities

# Multi-Project Auto-Workflow via .dir-locals.el

**Date:** 2026-03-28  
**Approach:** Option B - Repository-level configuration using standard Emacs mechanisms

## Problem

Original auto-workflow was hardcoded for single project (`~/.emacs.d`).

## Solution

Use Emacs' built-in `.dir-locals.el` mechanism for per-project configuration.

## How It Works

### 1. Project Detection Priority

`gptel-auto-workflow--project-root` now checks in order:

1. **Override variable** (from .dir-locals.el)
   - `gptel-auto-workflow--project-root-override`
2. **Git root** (auto-detected)
   - `git rev-parse --show-toplevel`
3. **Fallback**
   - `~/.emacs.d/`

### 2. Configuration via .dir-locals.el

Place `.dir-locals.el` in project root:

```elisp
((nil
  . ((gptel-auto-workflow--project-root-override . "/path/to/project")
     (gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
     (gptel-auto-experiment-max-per-target . 5)
     (gptel-auto-experiment-time-budget . 1200)
     (gptel-backend . gptel--dashscope)
     (gptel-model . qwen3.5-plus))))
```

### 3. Benefits

- **Standard Emacs mechanism** - No custom loading code
- **Automatic loading** - Loaded when visiting any file in project
- **Per-project isolation** - Each project has its own targets and settings
- **Git or non-git** - Works with any directory structure

## Usage

### For Git Projects

1. Create `.dir-locals.el` in project root
2. Set `gptel-auto-workflow-targets` for that project
3. Auto-workflow will use git root automatically

### For Non-Git Projects

1. Create `.dir-locals.el` in project root
2. Set `gptel-auto-workflow--project-root-override` to absolute path
3. Auto-workflow will use that path instead of git detection

### Manual Switching

```elisp
M-x gptel-auto-workflow-set-project-root
```

## Files Changed

- `lisp/modules/gptel-tools-agent.el` - Updated project detection
- `.dir-locals.el` - Example configuration

## Session Architecture (Per Worktree)

```
┌─────────────────────────────────────────────────────────┐
│  WORKTREE: optimize/target-exp1                         │
│  (default-directory: worktree path)                     │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │
│  │  analyzer   │ │  executor   │ │   grader    │       │
│  │  subagent   │ │  subagent   │ │  subagent   │       │
│  └─────────────┘ └─────────────┘ └─────────────┘       │
│  All share worktree context                             │
└─────────────────────────────────────────────────────────┘
```

Each experiment worktree has its own context, and all subagents within that worktree share the same `default-directory`.

## Future Improvements

- Add `M-x gptel-auto-workflow-switch-project` for interactive switching
- Per-project cron jobs (currently all use ~/.emacs.d/)
- Project-specific agent directories


# Upstream PR Workflow

## Insight

When local defensive code reveals an upstream bug, extract the minimal fix for PR, keep defensive layers local.

## Workflow

```
λ pr_workflow(x).    discover(bug) → check(upstream_has_fix)
                     | ¬upstream_has_fix → create_branch(upstream/master)
                     | implement(minimal_fix) > defensive_framework
                     | commit(clear_message) → push(fork)
                     | gh_pr_create(upstream_repo) → wait_review
```

## Commands

```bash
# 1. Fetch latest upstream
git fetch upstream

# 2. Create clean branch from upstream
git checkout -b fix-<issue> upstream/master

# 3. Implement minimal fix (not defensive framework)

# 4. Commit with conventional message
git commit -m "Fix: <description>"

# 5. Push to fork
git push origin fix-<issue> -u

# 6. Create PR
gh pr create --repo <upstream-owner>/<upstream-repo> \
             --head <fork-owner>:fix-<issue> \
             --base master \
             --title "Fix: <description>" \
             --body "<problem>\n<root-cause>\n<solution>\n<testing>"
```

## PR Template Sections

1. **Problem** — What breaks, when, for whom
2. **Root Cause** — Why it happens (code-level)
3. **Solution** — What changed and why
4. **Testing** — How it was verified

## Minimal vs Defensive

| Approach | Upstream | Local |
|----------|----------|-------|
| Fix bug in happy path | ✅ PR | — |
| Add edge case handling | ⚠️ Maybe | ✅ Keep |
| Defensive safety net | ❌ No | ✅ Keep |
| Framework for resilience | ❌ No | ✅ Keep |

## Example PR

**PR #1305** — gptel nil/null tool names
- Core fix: `cond` instead of `if` in streaming parser
- Left local: `my/gptel--sanitize-tool-calls`, doom-loop detection
- Result: 20 lines added, 16 deleted, clean fix

## Captured

2026-03-23 — From PR #1305 for gptel nil/null tool names

💡 workflow-benchmark-gaps-closed

Closed 5 identified gaps in workflow benchmark system:

1. **CI Integration** - evolution.yml now processes workflow benchmarks from benchmarks/workflows/
2. **Anti-patterns** - Added 4 workflow-specific patterns to gptel-benchmark-anti-patterns:
   - phase-violation: Skipping required phases (P1→P3 without P2)
   - tool-misuse: Too many tool calls (>15 steps or >3 continuations)
   - context-overflow: Too much exploration without action
   - no-verification: Edit without read (changes not verified)
3. **Memory Retrieval** - `gptel-workflow-retrieve-memories` searches mementum for relevant context
4. **Trend Analysis** - `gptel-workflow-benchmark-trend-analysis` returns direction/velocity/recommendation
5. **Nil Guards** - All anti-pattern detection now handles missing plist fields gracefully

🔄 workflow-improve-plan-agent

Workflow plan-agent: 3 anti-patterns, 3 improvements applied