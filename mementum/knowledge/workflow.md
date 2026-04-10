---
title: Auto-Workflow System
status: active
category: knowledge
tags: [workflow, automation, gptel, autonomous, testing]
---

# Auto-Workflow System

The auto-workflow system enables autonomous AI-driven code improvement with human oversight. It creates isolated experiment branches, runs improvement attempts, evaluates results, and logs outcomes without requiring user interaction.

## Core Architecture

```
gptel-auto-workflow-run
  → worktree (magit-worktree)
  → executor subagent (gptel-agent--task)
  → grader subagent (LLM, JSON output)
  → benchmark (Eight Keys scoring)
  → comparator (keep/discard)
  → TSV log
```

## Branching Rules

### Naming Convention

```
optimize/{target-name}-{hostname}-exp{N}
```

**Example**: `optimize/retry-imacpro.taila8bdd.ts.net-exp1`

### Flow

1. Create worktree with optimize branch
2. Executor makes changes in worktree (isolated from main)
3. If improvement → commit to optimize branch
4. Push to `origin optimize/...` (NOT main!)
5. Human reviews and merges to main via PR

### Code Location

`gptel-tools-agent.el:1134`:

```elisp
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

### Lambda Definition

```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

### Critical Rule

**Never push directly to main.** Always push to `optimize/...` branch first, then merge via PR after human review.

---

## Autonomous Principle

### The Core Rule

Auto-workflow is fully autonomous. It **never** asks the user for:
- Confirmation
- Input
- Decision
- Clarification

Instead, it retries, tries alternative approaches, logs failures, and continues.

### Lambda Definition

```
λ autonomous(x).
    fail(x) → retry(x)
    | retry(x) → retry(x)
    | max_retries → log_and_continue
    | ¬ask(user)
    | ¬stop_for_input
```

### Prohibited Functions

| Never Use | Always Use Instead |
|-----------|-------------------|
| `y-or-n-p` | Retry logic |
| `yes-or-no-p` | Fallback paths |
| `read-from-minibuffer` | Error logging |
| `completing-read` | Continue to next task |
| `user-error` (recoverable) | Log and continue |

### Retry Pattern

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

### Why This Matters

- Auto-workflow runs at 2 AM unattended
- No human is watching to answer questions
- Each failure is an opportunity to try again
- Eventual success > immediate failure

---

## Multi-Project Configuration

### Using .dir-locals.el

Use Emacs' built-in `.dir-locals.el` mechanism for per-project configuration.

### Project Detection Priority

`gptel-auto-workflow--project-root` checks in order:

1. **Override variable** (from .dir-locals.el)
   - `gptel-auto-workflow--project-root-override`
2. **Git root** (auto-detected)
   - `git rev-parse --show-toplevel`
3. **Fallback**
   - `~/.emacs.d/`

### Configuration Example

```elisp
((nil
  . ((gptel-auto-workflow--project-root-override . "/path/to/project")
     (gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
     (gptel-auto-experiment-max-per-target . 5)
     (gptel-auto-experiment-time-budget . 1200)
     (gptel-backend . gptel--dashscope)
     (gptel-model . qwen3.5-plus))))
```

### Session Architecture (Per Worktree)

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

---

## E2E Bug: Deleted Buffer

### Symptoms

- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution
- Executor runs for 560s+ without completing changes
- No results logged to TSV file
- Error: `gptel callback error: (error "Selecting deleted buffer")`

### Root Cause

The `gptel-auto-workflow--advice-task-override` advice overrides `current-buffer` to return a fixed project buffer. If that buffer is killed during async execution, all callbacks fail.

### Fix Applied

1. Added `kill-buffer-query-functions` protection to prevent buffer kill during runs
2. Made `current-buffer` override check liveness each call, fall back if killed
3. Saved original `current-buffer` function before overriding to avoid recursion

### Result

- E2E test passed - experiment completed in 230s with `kept` decision
- Score improved: 0.40 → 0.41
- Commit `bae1b73` merged to staging

---

## Upstream PR Workflow

When local defensive code reveals an upstream bug, extract the minimal fix for PR while keeping defensive layers local.

### Workflow Lambda

```
λ pr_workflow(x).    discover(bug) → check(upstream_has_fix)
                     | ¬upstream_has_fix → create_branch(upstream/master)
                     | implement(minimal_fix) > defensive_framework
                     | commit(clear_message) → push(fork)
                     | gh_pr_create(upstream_repo) → wait_review
```

### Commands

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

### PR Template Sections

1. **Problem** — What breaks, when, for whom
2. **Root Cause** — Why it happens (code-level)
3. **Solution** — What changed and why
4. **Testing** — How it was verified

### Minimal vs Defensive Approach

| Approach | Upstream | Local |
|----------|----------|-------|
| Fix bug in happy path | ✅ PR | — |
| Add edge case handling | ⚠️ Maybe | ✅ Keep |
| Defensive safety net | ❌ No | ✅ Keep |
| Framework for resilience | ❌ No | ✅ Keep |

### Example

**PR #1305** — gptel nil/null tool names
- Core fix: `cond` instead of `if` in streaming parser
- Left local: `my/gptel--sanitize-tool-calls`, doom-loop detection
- Result: 20 lines added, 16 deleted, clean fix

---

## Benchmark System Improvements

### Gaps Closed

1. **CI Integration** - evolution.yml now processes workflow benchmarks from `benchmarks/workflows/`

2. **Anti-patterns** - Added 4 workflow-specific patterns:
   - `phase-violation`: Skipping required phases (P1→P3 without P2)
   - `tool-misuse`: Too many tool calls (>15 steps or >3 continuations)
   - `context-overflow`: Too much exploration without action
   - `no-verification`: Edit without read (changes not verified)

3. **Memory Retrieval** - `gptel-workflow-retrieve-memories` searches mementum for relevant context

4. **Trend Analysis** - `gptel-workflow-benchmark-trend-analysis` returns direction/velocity/recommendation

5. **Nil Guards** - All anti-pattern detection now handles missing plist fields gracefully

---

## Verification Results

### Test Results (2026-03-24)

| Step | Status | Duration | Details |
|------|--------|----------|---------|
| Worktree creation | ✓ | <1s | optimize/retry-exp1 |
| Executor subagent | ✓ | 80s | Made docstring changes |
| Grader subagent | ✓ | 10s | 6/6 behaviors passed |
| Benchmark | ✓ | 10s | Score 1.0 (no change) |
| Decision | ✓ | <1s | Discarded (no improvement) |
| TSV logging | ✓ | <1s | results.tsv created |

### Experiment 1 Results

```
target: gptel-ext-retry.el
hypothesis: Adding docstring to improve maintainability
score: 1.00 → 1.00 (no change)
decision: discarded
duration: 100s
grader: 6/6 passed
```

### Analyzer Recommendations

1. Add maintainability-specific metrics
2. Reduce evaluation overhead (100s excessive)
3. Separate scoring tracks: functional vs quality vs docs
4. Weight scores by change category

---

## Key Files

| File | Purpose |
|------|---------|
| `gptel-tools-agent.el` | Main workflow implementation |
| `var/tmp/experiments/2026-03-24/results.tsv` | Experiment log |
| `.dir-locals.el` | Per-project configuration |
| `benchmarks/workflows/` | Benchmark definitions |
| `evolution.yml` | CI workflow for benchmarks |

---

## Related

- [gptel-agent][gptel-agent] - The underlying agent system
- [git-worktree][git-worktree] - Emacs worktree integration
- [benchmark-system][benchmark-system] - Scoring and evaluation
- [autonomous-principles][autonomous-principles] - Core autonomy rules
- [upstream-contribution][upstream-contribution] - PR workflow patterns
- [dir-locals][dir-locals] - Emacs per-directory configuration

---

## Lambda Summary

```
λ workflow. worktree → executor → grader → benchmark → decide → log
λ branch. optimize/{target}-{hostname}-exp{N}
λ autonomous. fail → retry → retry → log_continue → ¬ask
λ multi-project. .dir-locals.el → per-project targets
λ pr. minimal_fix → upstream, defensive → local
λ verified. All steps work, TSV created
```