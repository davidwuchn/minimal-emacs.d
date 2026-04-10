---
title: Auto-Workflow System
status: active
category: knowledge
tags: [workflow, automation, autonomous, gptel, benchmarking]
---

# Auto-Workflow System

The auto-workflow system is a fully autonomous improvement pipeline that runs AI-driven experiments against codebase targets without human intervention. This knowledge page documents the core patterns, configurations, and lessons learned from building and operating this system.

## Core Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AUTO-WORKFLOW PIPELINE                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────┐    ┌───────────┐    ┌─────────┐    ┌─────────────┐  │
│  │ Analyzer│───▶│ Executor  │───▶│  Grader │───▶│  Benchmark  │  │
│  │         │    │  subagent │    │         │    │             │  │
│  └─────────┘    └───────────┘    └─────────┘    └─────────────┘  │
│       │                                                   │        │
│       ▼                                                   ▼        │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    DECISION ENGINE                         │   │
│  │              (keep/discard based on score delta)            │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                     │
│                              ▼                                     │
│                      ┌──────────────┐                              │
│                      │ TSV Logging  │                              │
│                      │ results.tsv  │                              │
│                      └──────────────┘                              │
└─────────────────────────────────────────────────────────────────────┘
```

## Branching Strategy

### Auto-Workflow Branching Rule

The system uses an isolation-first branching model to prevent unreviewed changes from reaching the main branch.

**Rule Definition:**
```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

**Branch Format:**
```
optimize/{target-name}-{hostname}-exp{N}
```

**Example:**
```
optimize/retry-imacpro.taila8bdd.ts.net-exp1
```

### Branch Flow

1. **Create worktree** with optimize branch (`magit-worktree`)
2. **Executor** makes changes in worktree (isolated from main)
3. **If improvement** → commit to optimize branch
4. **Push** to `origin optimize/...` (NOT main!)
5. **Human reviews** and merges to main via PR

### Push Implementation

From `gptel-tools-agent.el:1134`:

```elisp
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

**Critical Rule:** Always verify branch is `optimize/...` before pushing. Never push directly to main.

## Multi-Project Configuration

### Project Detection Priority

The system checks project root in this order:

| Priority | Source | Variable |
|----------|--------|----------|
| 1 | Override variable | `gptel-auto-workflow--project-root-override` |
| 2 | Git root (auto-detected) | `git rev-parse --show-toplevel` |
| 3 | Fallback | `~/.emacs.d/` |

### Configuration via .dir-locals.el

Add to project root `.dir-locals.el`:

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

## The "Never Ask" Principle

### Core Definition

```
λ autonomous(x).
    fail(x) → retry(x)
    | retry(x) → retry(x)
    | max_retries → log_and_continue
    | ¬ask(user)
    | ¬stop_for_input
```

Auto-workflow is fully autonomous. It never asks the user for confirmation, input, decision, or clarification. Instead, it retries, tries alternative approaches, logs failures, and continues.

### What This Means

- **Auto-workflow runs at 2 AM** unattended
- **No human is watching** to answer questions
- **Each failure is an opportunity** to try again
- **Eventual success > immediate failure**

### Forbidden Functions in Auto-Workflow

| Never Use | Instead Use |
|-----------|-------------|
| `y-or-n-p` | Retry logic |
| `yes-or-no-p` | Fallback paths |
| `read-from-minibuffer` | Error logging |
| `completing-read` | Continue to next task |
| `user-error` (for recoverable issues) | Logging with `message` |

### Retry Pattern Implementation

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

### Failure Handling Examples

| Failure | Don't Do This | Do This |
|---------|---------------|---------|
| Worktree create fails | Ask user "Retry?" | Retry automatically |
| Test fails | Ask "Continue?" | Log and continue to next target |
| LLM timeout | Ask "What now?" | Retry with shorter prompt |
| Push fails | Ask "Force push?" | Retry with fresh auth |

## Bug Fixes and Improvements

### E2E Bug: Deleted Buffer

**Discovery:** During e2e test, auto-workflow fails with "Selecting deleted buffer" error.

**Symptoms:**
- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution
- Executor runs for 560s+ without completing changes
- No results logged to TSV file
- Error: `gptel callback error: (error "Selecting deleted buffer")`

**Root Cause:**
The `gptel-auto-workflow--advice-task-override` advice overrides `current-buffer` to return a fixed project buffer. If that buffer is killed during async execution, all callbacks fail.

**Fix Applied:**

```elisp
;; 1. Add kill-buffer-query-functions protection
(add-hook 'kill-buffer-query-functions
          (lambda ()
            (if gptel-auto-workflow-running
                (progn
                  (message "Preventing buffer kill during workflow")
                  nil)
              t)))

;; 2. Check liveness each call, fall back if killed
(advice-add 'current-buffer :around
  (lambda (orig-fun &rest args)
    (if (buffer-live-p gptel-auto-workflow--project-buffer)
        (funcall orig-fun args)
      (or (buffer-local-value 'gptel-auto-workflow--original-current-buffer
                              (current-buffer))
          (current-buffer)))))
```

**Result:**
- E2E test passed - experiment completed in 230s with `kept` decision
- Score improved: 0.40 → 0.41
- Commit `bae1b73` merged to staging

### Plan-Agent Improvements

Applied 3 improvements for 3 anti-patterns detected in workflow plan-agent:

1. Phase violations → Added phase-order enforcement
2. Tool misuse → Added step count limits
3. Context overflow → Added exploration bounds

## Verification Results

### E2E Test - 2026-03-24

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

### Issues Identified

1. **API timeouts**: DashScope slow, curl exit 28, retries needed
2. **No score improvement**: Metrics don't capture docstring value
3. **Long duration**: 100s for simple docstring change

## Upstream PR Workflow

When local defensive code reveals an upstream bug, extract the minimal fix for PR while keeping defensive layers local.

### Workflow Definition

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

**Example:** PR #1305 for gptel nil/null tool names
- Core fix: `cond` instead of `if` in streaming parser
- Left local: `my/gptel--sanitize-tool-calls`, doom-loop detection
- Result: 20 lines added, 16 deleted, clean fix

## Benchmark System Improvements

### Closed Gaps

1. **CI Integration** - `evolution.yml` now processes workflow benchmarks from `benchmarks/workflows/`

2. **Anti-patterns** - Added 4 workflow-specific patterns:
   - `phase-violation`: Skipping required phases (P1→P3 without P2)
   - `tool-misuse`: Too many tool calls (>15 steps or >3 continuations)
   - `context-overflow`: Too much exploration without action
   - `no-verification`: Edit without read (changes not verified)

3. **Memory Retrieval** - `gptel-workflow-retrieve-memories` searches mementum for relevant context

4. **Trend Analysis** - `gptel-workflow-benchmark-trend-analysis` returns direction/velocity/recommendation

5. **Nil Guards** - All anti-pattern detection now handles missing plist fields gracefully

## Actionable Patterns Summary

### For New Workflow Implementations

1. **Always use optimize branches** - Never push directly to main
2. **Implement retry logic** - Never block waiting for user input
3. **Use .dir-locals.el** - For multi-project support
4. **Check buffer liveness** - Before using cached buffer references
5. **Extract minimal upstream fixes** - Keep defensive code local

### For Debugging Workflow Failures

1. Check branch name before push operations
2. Verify buffer isn't killed during async operations
3. Ensure retry count isn't exhausted
4. Check TSV output for score deltas

### For Contributing Upstream

1. Verify upstream doesn't already have the fix
2. Create branch from `upstream/master`
3. Implement only the minimal fix
4. Use conventional commit messages

## Related

- [Auto-Workflow Configuration](auto-workflow-config)
- [Benchmark Anti-Patterns](benchmark-anti-patterns)
- [Gptel Agent](gptel-agent)
- [Project Detection](project-detection)
- [Subagent Communication](subagent-communication)
- [Git Worktree Strategy](git-worktree)
- [Upstream Contribution](upstream-contribution)