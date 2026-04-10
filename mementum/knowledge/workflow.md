---
title: Auto-Workflow System
status: active
category: knowledge
tags: [workflow, auto-workflow, gptel-agent, experimentation, branching]
---

# Auto-Workflow System

The auto-workflow system enables autonomous code improvement through a structured experimentation pipeline. It creates isolated worktrees, runs executor subagents to make changes, grades the results, and logs decisions—all without human intervention.

## Core Architecture

```
gptel-auto-workflow-run
  ├── worktree creation (magit-worktree)
  ├── analyzer subagent (hypothesis generation)
  ├── executor subagent (code changes)
  ├── grader subagent (behavior verification)
  ├── benchmark (Eight Keys scoring)
  ├── comparator (keep/discard decision)
  └── TSV logging
```

Each experiment runs in a dedicated worktree, allowing parallel optimization of multiple targets without interference.

---

## Branching Strategy

### The Auto-Workflow Branching Rule

All auto-experiments run on `optimize/` branches, never on `main` directly.

```elisp
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

### Branch Naming Convention

Format: `optimize/{target-name}-{hostname}-exp{N}`

| Component | Description | Example |
|-----------|-------------|---------|
| `optimize/` | Prefix for experiment branches | `optimize/` |
| `{target-name}` | Target file or module name | `retry-imacpro` |
| `{hostname}` | Machine identifier | `taila8bdd.ts.net` |
| `exp{N}` | Experiment sequence number | `exp1` |

**Full Example**: `optimize/retry-imacpro.taila8bdd.ts.net-exp1`

### Push Behavior

```elisp
;; From gptel-tools-agent.el:1134
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

**Critical Rule**: Always verify branch before pushing. On 2026-03-25, a push was mistakenly made directly to main—this violated the branching rule.

### Flow

1. Create worktree with `optimize/` branch
2. Executor makes changes in isolated worktree
3. If improvement detected → commit to optimize branch
4. Push to `origin optimize/...` (NOT main)
5. Human reviews via PR and merges to main

**Why This Matters**:
- Prevents unreviewed AI changes on main
- Multiple machines can optimize same target without conflicts
- Human gate for quality control

---

## Configuration via .dir-locals.el

### Project Detection Priority

`gptel-auto-workflow--project-root` checks in this order:

1. **Override variable** (from .dir-locals.el)
   - `gptel-auto-workflow--project-root-override`
2. **Git root** (auto-detected)
   - `git rev-parse --show-toplevel`
3. **Fallback**
   - `~/.emacs.d/`

### Example Configuration

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

### Manual Switching

```elisp
M-x gptel-auto-workflow-set-project-root
```

### Benefits

- **Standard Emacs mechanism** - No custom loading code
- **Automatic loading** - Loaded when visiting any file in project
- **Per-project isolation** - Each project has its own targets and settings
- **Git or non-git** - Works with any directory structure

---

## Core Principle: Never Ask User

### The Autonomy Rule

```
λ autonomous(x).
    fail(x) → retry(x)
    | retry(x) → retry(x)
    | max_retries → log_and_continue
    | ¬ask(user)
    | ¬stop_for_input
```

Auto-workflow is fully autonomous. It never asks the user for:
- Confirmation
- Input
- Decision
- Clarification

Instead, it retries, tries alternative approaches, logs failures, and continues.

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

### Failure Handling Matrix

| Failure | Don't Do This | Do This |
|---------|---------------|---------|
| Worktree create fails | Ask user "Retry?" | Retry automatically |
| Test fails | Ask "Continue?" | Log and continue to next target |
| LLM timeout | Ask "What now?" | Retry with shorter prompt |
| Push fails | Ask "Force push?" | Retry with fresh auth |

### Prohibited Functions

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

---

## Bug Fix: Deleted Buffer

### Discovery

During e2e test, auto-workflow failed with "Selecting deleted buffer" error.

**Symptoms:**
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

## Verification Results

### Test Run (2026-03-24)

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

### Identified Issues

1. **API timeouts**: DashScope slow, curl exit 28, retries needed
2. **No score improvement**: Metrics don't capture docstring value
3. **Long duration**: 100s for simple docstring change

---

## Upstream PR Workflow

When local defensive code reveals an upstream bug, extract the minimal fix for PR while keeping defensive layers local.

### Workflow

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

### Minimal vs Defensive

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

## Anti-Patterns and Benchmark Gaps

### Workflow-Specific Anti-Patterns

Added to `gptel-benchmark-anti-patterns`:

| Pattern | Description | Detection |
|---------|-------------|-----------|
| `phase-violation` | Skipping required phases (P1→P3 without P2) | Phase sequence validation |
| `tool-misuse` | Too many tool calls (>15 steps or >3 continuations) | Call count threshold |
| `context-overflow` | Too much exploration without action | Exploration/action ratio |
| `no-verification` | Edit without read (changes not verified) | Read after edit check |

### Gap Closures

1. **CI Integration** - `evolution.yml` now processes workflow benchmarks from `benchmarks/workflows/`
2. **Memory Retrieval** - `gptel-workflow-retrieve-memories` searches mementum for relevant context
3. **Trend Analysis** - `gptel-workflow-benchmark-trend-analysis` returns direction/velocity/recommendation
4. **Nil Guards** - All anti-pattern detection now handles missing plist fields gracefully

### Analyzer Recommendations

1. Add maintainability-specific metrics
2. Reduce evaluation overhead (100s excessive)
3. Separate scoring tracks: functional vs quality vs docs
4. Weight scores by change category

---

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

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `lisp/modules/gptel-tools-agent.el` | Main workflow implementation |
| `var/tmp/experiments/2026-03-24/results.tsv` | Experiment log |
| `var/tmp/experiments/optimize/retry-exp1/` | Worktree (cleaned up) |
| `.dir-locals.el` | Per-project configuration |
| `benchmarks/workflows/` | Workflow benchmark data |

---

## Related

- [Auto-Workflow Configuration](workflow-config)
- [Gptel-Agent Architecture](gptel-agent)
- [Benchmark System](benchmark)
- [Upstream Contribution](upstream-pr)
- [Emacs Worktrees](magit-worktree)
- [Subagent Patterns](subagents)