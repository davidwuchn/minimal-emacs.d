---
title: Auto-Workflow System
status: active
category: knowledge
tags: [workflow, automation, gptel, agent, emacs]
---

# Auto-Workflow System

The auto-workflow system enables autonomous code improvement through a structured pipeline that creates experiments in isolated worktrees, evaluates changes via graders, and logs results for analysis. This document covers the branching model, bug fixes, autonomy principles, multi-project support, upstream PR workflow, and benchmark integration.

## Branching Model

### The Auto-Workflow Branching Rule

Auto-workflow creates experimental branches in the `optimize/` namespace to isolate AI-generated changes from the main branch until human review.

```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

**Branch Format**: `optimize/{target-name}-{hostname}-exp{N}`

| Component | Description | Example |
|-----------|-------------|---------|
| namespace | Always `optimize/` | `optimize/` |
| target | File or feature being improved | `retry-imacpro.taila8bdd.ts.net` |
| hostname | Machine identifier | `taila8bdd.ts.net` |
| expN | Experiment iteration | `exp1` |

**Full Example**: `optimize/retry-imacpro.taila8bdd.ts.net-exp1`

### Branch Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    BRANCH WORKFLOW                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. create        2. executor          3. push                │
│   ┌──────┐        ┌──────────┐        ┌──────────────┐        │
│   │main  │───fork─→│optimize/ │───push─→│origin        │        │
│   │      │        │expN work-│        │optimize/expN │        │
│   │      │        │tree      │        │              │        │
│   └──────┘        └──────────┘        └──────────────┘        │
│                       │                                     │   │
│                       │ 4. human review                    │   │
│                       └───────────────merge──────────────┘   │
│                                      ↓                       │
│                               ┌──────────────┐               │
│                               │    main      │               │
│                               │ (reviewed)   │               │
│                               └──────────────┘               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation

**Elisp Code** (`gptel-tools-agent.el:1134`):
```elisp
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

**Git Commands**:
```bash
# Create worktree with optimize branch
git worktree add -b optimize/target-exp1 /path/to/worktree main

# Push to origin (NOT main!)
git push origin optimize/target-exp1

# After human review, merge to main
git checkout main
git merge origin/optimize/target-exp1
```

### Common Mistake

⚠️ **Never push auto-workflow changes directly to main.** This violates the branching rule and bypasses human review.

```bash
# WRONG - direct push to main
git push origin main

# CORRECT - push to optimize branch
git push origin optimize/target-exp1
```

## E2E Bug: Deleted Buffer

### Symptoms

During end-to-end testing, auto-workflow fails with:
- Error: `gptel callback error: (error "Selecting deleted buffer")`
- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution
- Executor runs 560+ seconds without completing
- No results logged to TSV file

### Root Cause

The advice `gptel-auto-workflow--advice-task-override` overrides `current-buffer` to return a fixed project buffer. If that buffer is killed during async execution, all callbacks fail.

### Fix Applied

```elisp
;; 1. Prevent buffer kill during runs
(add-to-list 'kill-buffer-query-functions 
             #'gptel-auto-workflow--protect-buffer)

;; 2. Check buffer liveness each call
(defun gptel-auto-workflow--current-buffer-safe ()
  "Return current buffer, checking liveness."
  (if (buffer-live-p gptel-auto-workflow--project-buffer)
      gptel-auto-workflow--project-buffer
    (funcall original-current-buffer)))

;; 3. Save original before overriding
(defvar gptel-auto-workflow--original-current-buffer 
        (symbol-function 'current-buffer))
```

### Results

| Metric | Before | After |
|--------|--------|-------|
| Duration | 560s+ (timeout) | 230s |
| Result | Failed | Passed (kept) |
| Score | 0.40 | 0.41 |
| Commit | — | bae1b73 |

## Autonomy Principle

### The Rule: Never Ask User

Auto-workflow is fully autonomous. It never halts for user input.

```
λ autonomous(x).
    fail(x) → retry(x)
    | retry(x) → retry(x)
    | max_retries → log_and_continue
    | ¬ask(user)
    | ¬stop_for_input
```

### What This Means

| Never Do This | Always Do This |
|---------------|----------------|
| `y-or-n-p` | Retry automatically |
| `yes-or-no-p` | Log and continue |
| `read-from-minibuffer` | Try alternative approach |
| `completing-read` | Fallback path |
| `user-error` (recoverable) | Error logging |

### Retry Pattern

```elisp
(defun gptel-auto-workflow--with-retry (fn max-retries &optional delay)
  "Call FN, retry on failure, never ask user."
  (let ((attempts 0)
        (delay (or delay 1)))
    (while (< attempts max-retries)
      (cl-incf attempts)
      (condition-case err
          (funcall fn)
        (error
         (message "Attempt %d/%d failed: %s" 
                  attempts max-retries (error-message-string err))
         (when (< attempts max-retries)
           (sleep-for delay)))))))

;; Usage: never block on user input
(gptel-auto-workflow--with-retry 
 (lambda () (gptel-agent--task "fix-bug")) 
 3)
```

### Failure Handling Table

| Failure | Recovery Strategy |
|---------|-------------------|
| Worktree create fails | Retry with exponential backoff |
| Test fails | Log, continue to next target |
| LLM timeout | Retry with shorter prompt |
| Push fails | Retry with fresh auth |
| API rate limit | Wait and retry |

### Verification Results

**Date**: 2026-03-24

| Step | Status | Duration | Details |
|------|--------|----------|---------|
| Worktree creation | ✓ | <1s | optimize/retry-exp1 |
| Executor subagent | ✓ | 80s | Made docstring changes |
| Grader subagent | ✓ | 10s | 6/6 behaviors passed |
| Benchmark | ✓ | 10s | Score 1.0 (no change) |
| Decision | ✓ | <1s | Discarded (no improvement) |
| TSV logging | ✓ | <1s | results.tsv created |

**Full Flow Verified**:
```
gptel-auto-workflow-run
  → worktree (magit-worktree)
  → executor subagent (gptel-agent--task)
  → grader subagent (LLM, JSON output)
  → benchmark (Eight Keys scoring)
  → comparator (keep/discard)
  → TSV log
```

## Multi-Project Configuration

### Using .dir-locals.el

Auto-workflow supports multiple projects via Emacs' built-in `.dir-locals.el` mechanism.

### Project Detection Priority

```
gptel-auto-workflow--project-root:
  1. gptel-auto-workflow--project-root-override  (from .dir-locals.el)
  2. git rev-parse --show-toplevel              (auto-detected)
  3. ~/.emacs.d/                                (fallback)
```

### Configuration Example

Create `.dir-locals.el` in project root:

```elisp
((nil
  . ((gptel-auto-workflow--project-root-override . "/path/to/project")
     (gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
     (gptel-auto-experiment-max-per-target . 5)
     (gptel-auto-experiment-time-budget . 1200)
     (gptel-backend . gptel--dashscope)
     (gptel-model . qwen3.5-plus))))
```

### Manual Switching

```elisp
M-x gptel-auto-workflow-set-project-root
```

### Session Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  WORKTREE: optimize/target-exp1                             │
│  (default-directory: worktree path)                          │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            │
│  │  analyzer   │ │  executor   │ │   grader    │            │
│  │  subagent   │ │  subagent   │ │  subagent   │            │
│  └─────────────┘ └─────────────┘ └─────────────┘            │
│  All share worktree context                                  │
└─────────────────────────────────────────────────────────────┘
```

Each experiment worktree has its own context, and all subagents within that worktree share the same `default-directory`.

## Upstream PR Workflow

### When to Create Upstream PR

When local defensive code reveals an upstream bug, extract the minimal fix for PR while keeping defensive layers local.

```
λ pr_workflow(x).
    discover(bug) → check(upstream_has_fix)
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

### PR Template

1. **Problem** — What breaks, when, for whom
2. **Root Cause** — Why it happens (code-level)
3. **Solution** — What changed and why
4. **Testing** — How it was verified

### Minimal vs Defensive

| Approach | Upstream PR | Keep Local |
|----------|-------------|------------|
| Fix bug in happy path | ✅ | — |
| Add edge case handling | ⚠️ Maybe | ✅ |
| Defensive safety net | ❌ No | ✅ |
| Framework for resilience | ❌ No | ✅ |

**Example**: PR #1305 for gptel nil/null tool names
- Core fix: `cond` instead of `if` in streaming parser
- Left local: `my/gptel--sanitize-tool-calls`, doom-loop detection
- Result: 20 lines added, 16 deleted, clean fix

## Benchmark System

### Workflow Anti-Patterns

Four workflow-specific patterns added to `gptel-benchmark-anti-patterns`:

| Pattern | Description | Detection |
|---------|-------------|-----------|
| phase-violation | Skipping required phases (P1→P3 without P2) | Check phase sequence |
| tool-misuse | >15 tool calls or >3 continuations | Count calls per turn |
| context-overflow | Too much exploration without action | Measure explore/act ratio |
| no-verification | Edit without read | Verify read before write |

### CI Integration

`evolution.yml` now processes workflow benchmarks from `benchmarks/workflows/`:

```yaml
- name: Workflow Benchmarks
  run: |
    emacs --batch \
          --eval "(setq gptel-benchmark-dir \"benchmarks/workflows/\")" \
          -l gptel-workflow-benchmark.el \
          -f gptel-workflow-run-all
```

### Memory Retrieval

```elisp
(gptel-workflow-retrieve-memories query)
;; Returns relevant context from mementum
```

### Trend Analysis

```elisp
(gptel-workflow-benchmark-trend-analysis)
;; Returns: (direction velocity recommendation)
;; direction: improving/degrading/stable
;; velocity: changes per period
;; recommendation: actionable improvement
```

### Nil Guards

All anti-pattern detection now handles missing plist fields gracefully:

```elisp
;; Before: would error on missing :phase
(when (eq (plist-get turn :phase) 'verify) ...)

;; After: safe access
(when (eq (plist-get turn :phase 'unknown) 'verify) ...)
```

## Related

- [gptel-agent](./gptel-agent.md) — Executor subagent implementation
- [benchmark-system](./benchmark-system.md) — Scoring and comparison
- [memory-system](./memory-system.md) — Mementum integration
- [project-configuration](./project-configuration.md) — .dir-locals.el details
- [git-worktree](./git-worktree.md) — Worktree management

---

**Status**: Active  
**Last Updated**: 2026-03-28  
**Key Files**: `lisp/modules/gptel-tools-agent.el`, `.dir-locals.el`