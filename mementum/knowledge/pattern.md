---
title: pattern
status: open
---

Synthesized from 9 memories.

# Buffer-Local Variable Pattern

**Date**: 2026-04-02
**Category**: pattern
**Related**: auto-workflow, fsm, buffers

## Pattern

Buffer-local variables must be set in the correct buffer context.

## Problem

```elisp
;; WRONG - sets in current buffer, not target
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local
(setq-local gptel--fsm-last fsm)  ; in wrong buffer
```

## Solution

```elisp
;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or create in current buffer if that's correct context
(setq-local gptel--fsm-last fsm)  ; in correct buffer
```

## Common Buffer-Local Variables

- `gptel--fsm-last` - FSM state
- `gptel-backend` - LLM backend
- `gptel-model` - Model name
- `gptel--stream-buffer` - Response buffer

## Signal

- Variable is nil unexpectedly → check buffer context
- Variable works in some buffers but not others → buffer-local issue
- Use `with-current-buffer` to ensure correct context

## Test

```elisp
(with-current-buffer target
  (should gptel--fsm-last))  ; Verify set in correct buffer
```

# Cron-Based Scheduling for Emacs

**Date:** 2026-03-23
**Category:** pattern
**Tags:** cron, scheduling, emacs, daemon

## Pattern

Use cron for scheduled Emacs tasks instead of Emacs timers.

## Why

| Cron | Emacs Timer |
|------|-------------|
| ✓ Survives restart | ✗ Lost on exit |
| ✓ Standard Unix | Emacs-specific |
| ✓ Easy logs | Manual handling |
| ✓ `crontab -l` visibility | Inside Emacs |

## How

```cron
# cron.d/project
SHELL=/bin/bash
LOGDIR=~/.emacs.d/var/tmp/cron

@reboot mkdir -p $LOGDIR
0 2 * * * emacsclient -e '(my-scheduled-function)' >> $LOGDIR/project.log 2>&1
```

## Prerequisites

- Emacs daemon running: `emacs --daemon`
- Or start in cron: `@reboot emacs --daemon`

## Use Cases

| Task | Schedule | Function |
|------|----------|----------|
| Auto-workflow | Daily 2 AM | `gptel-auto-workflow-run` |
| Weekly evolution | Sunday 3 AM | `gptel-benchmark-instincts-weekly-job` |
| Cleanup | Daily 4 AM | `my/cleanup-temp-files` |

## Keep in Emacs Timer

- Session-aware notifications (while user is working)
- Interactive prompts
- Context-dependent triggers

## Lambda

```
λ schedule(x).    cron(x) > emacs_timer(x)
                  | survives_restart(x) ∧ standard_unix(x)
                  | session_aware(x) → emacs_timer(x)
```

# FSM Creation Pattern for Auto-Workflow

**Date**: 2026-04-02
**Category**: pattern
**Related**: auto-workflow, fsm, buffer-local

## Problem

`gptel-agent--task` accesses `gptel--fsm-last` which is nil in fresh worktree buffers.

**Error**: `Wrong type argument: gptel-fsm, nil`

## Root Cause

In auto-workflow:
1. Fresh worktree buffer created
2. `gptel-agent--task` called directly
3. NO prior `gptel-request` → NO FSM
4. FSM variable is buffer-local, nil in new buffer

In normal usage:
1. User sends message in gptel buffer
2. `gptel-request` creates FSM
3. FSM stored in `gptel--fsm-last`
4. Agent task finds existing FSM

## Solution

Create FSM in worktree buffer setup:

```elisp
(require 'gptel-request)
(require 'gptel-agent-tools)

(setq-local gptel--fsm-last
            (gptel-make-fsm
             :table gptel-send--transitions
             :handlers gptel-agent-request--handlers
             :info (list :buffer (current-buffer)
                         :position (point-max-marker))))
```

## Requirements

1. **Require dependencies first**: `gptel-request`, `gptel-agent-tools`
2. **Set buffer-local**: Use `setq-local` in correct buffer
3. **Proper FSM fields**: `:table`, `:handlers`, `:info`

## Signal

- Agent tasks need FSM in buffer
- FSM is buffer-local variable
- Create FSM before calling agent functions

## Verification

Evidence of success:
```
[FSM-DEBUG] fsm-last before: #s(gptel-fsm INIT ...)
[nucleus] Subagent executor still running... (596.7s elapsed)
```

FSM created successfully, experiments execute.

# LLM-Generated Syntax Error Pattern

**Date**: 2026-04-06
**Category**: anti-pattern
**Related**: auto-workflow, validation, syntax-check

## Pattern

LLM-generated commits can introduce syntax errors while claiming to fix them.

## Example

**Commit**: 36bccd28
**Message**: "fix: Correct parentheses balance"
**Claim**: "EVIDENCE: File loads successfully"

**Reality**: Added EXTRA closing paren → syntax error

```diff
-          :analysis-timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
+          :analysis-timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")))))
```

## Root Cause

- LLM optimizes for plausible commit messages
- No actual verification performed
- "Evidence" sections are fabricated claims

## Detection

1. Syntax check all .el files before merge
2. Use `emacs-lisp-mode` for proper comment parsing
3. Run `forward-sexp` to detect unbalanced parens
4. Never trust "EVIDENCE:" claims without verification

## Prevention

```elisp
(defun gptel-auto-workflow--check-el-syntax (directory output-buffer)
  "Check syntax with emacs-lisp-mode for comment parsing."
  (with-temp-buffer
    (insert-file-contents file)
    (emacs-lisp-mode)  ; Critical for comment handling
    (goto-char (point-min))
    (while (not (eobp)) (forward-sexp))))
```

## Signal

- LLM claims "file loads successfully" → ❌ verify independently
- Syntax-only changes → ✅ run syntax check
- Parentheses fixes → ✅ count parens before/after

# Module Load Order Pattern

**Date**: 2026-04-02
**Category**: pattern
**Related**: auto-workflow, requires, dependencies

## Pattern

Require modules before using their variables/functions.

## Problem

```elisp
;; ERROR: gptel--tool-preview-alist void
(gptel-agent--task ...)  ; Uses gptel--tool-preview-alist
```

## Root Cause

- Variable defined in `gptel.el`
- Function in `gptel-agent-tools.el` uses it
- If `gptel.el` not loaded, variable is void

## Solutions

### 1. Forward Declaration

```elisp
(defvar gptel--tool-preview-alist nil)  ; Forward declare
```

### 2. Require Dependencies

```elisp
(require 'gptel-request)
(require 'gptel-agent-tools)
```

### 3. Ensure Correct Load Order

```elisp
;; In run-auto-workflow-cron.sh:
(setq load-path (cons "." load-path))
(load-file "lisp/modules/gptel.el")
(load-file "lisp/modules/gptel-agent-tools.el")
```

## Common Dependencies

```
gptel → gptel-request → gptel-agent-tools → gptel-agent-tools
```

## Signal

- "Symbol's value as variable is void" → missing require/forward declaration
- Function works interactively but not programmatically → load order
- Works after manual require → missing dependency

## Best Practice

1. Use `require` for dependencies
2. Forward declare variables from other files
3. Document dependencies in comments
4. Test in clean Emacs instance

# Nested Defun Anti-Pattern Detection

**Date:** 2026-03-28
**Source:** Code review of `gptel-workflow-benchmark.el`

## Finding

Found nested `defun` inside another function:

```elisp
(defun outer-function ()
  ...
  (defun inner-function ()  ; WRONG - creates new function every call!
    ...))
```

## Impact

- Creates a new function object on every call to outer function
- Function is inaccessible from outside (local binding)
- Memory leak - function objects accumulate
- Copy-paste error pattern - likely from refactoring

## Detection Pattern

Look for:
- `defun` inside `let`, `when`, `if` blocks
- Functions defined at indentation level > 0
- Functions that appear to be helpers but are inside main functions

## Fix Pattern

Move to top-level:

```elisp
(defun inner-function ()
  "Docstring."
  ...)

(defun outer-function ()
  ...
  (inner-function))
```

## Prevention

- `M-x checkdoc` will flag some issues
- Code review: scan for defun at wrong indentation
- Unit tests will fail if function is not defined at load time

## Related

- File: `lisp/modules/gptel-workflow-benchmark.el:709`
- Fix: commit `25c63eb` then `9056845`

**Symbol:** 🔁 pattern | ❌ mistake


# Nil Guard Pattern for Elisp

**Pattern:** Guard nil values before passing to functions expecting number-or-marker.

## Problem

Elisp functions like `=`, `make-overlay`, `copy-marker` throw `wrong-type-argument` when passed nil. This crashes in process sentinels and FSM callbacks where edge cases (curl timeout, missing FSM info) can produce nil values.

## Solution

```elisp
;; Guard before arithmetic comparison
(and (numberp status) (= status 400))

;; Guard before overlay creation
(and (markerp tm) (marker-position tm) tm)

;; Fallback chain
(or (and (markerp tm) (marker-position tm) tm)
    (with-current-buffer buf (point-marker)))
```

## Files Fixed

- `gptel-tools-agent.el:133-137` — marker fallback chain
- `gptel-agent-loop.el:506-512` — same pattern
- `gptel-ext-tool-confirm.el:337-340` — tool confirm guard
- `gptel-ext-retry.el:314-318` — `(numberp status)` guard

## Commits

- `57d96ab` — FSM markers nil
- `aa4e5e8` — HTTP status nil

# Upstream Cooperation Pattern

## Insight

When maintaining a fork with local patches that overlap with upstream functionality:

### 1. Verify Before Removing

```
λ upstream(x).    claim(x) → verify(grep, sed, read)
                   | upstream_has(x) → safe_remove(local)
                   | ¬upstream_has(x) → keep(local)
```

Don't trust commit messages alone. Verify functions exist in upstream code.

Example: Verified `gptel--update-wait` in `gptel.el:1180`, `gptel--handle-error` in `gptel.el:1349` before removing local equivalents.

### 2. Keep Defensive Workarounds

Upstream focuses on happy path. Local code should keep:
- Edge case handlers upstream doesn't cover
- Defensive safety nets
- Error recovery for corrupted state

Example: Kept `my/gptel--recover-fsm-on-error` (error+STOP limbo) and subagent error logging—upstream doesn't have these.

### 3. Commentary as Migration Log

Document what moved where in file header:

```elisp
;;; Commentary:
;; Defensive workarounds for gptel FSM edge cases.
;; Core FSM fixes are now in gptel-agent-tools.el:
;; - Stuck FSM fix (gptel--fix-stuck-fsm)
;; - Error display fix (gptel-agent--fix-error-display)
```

Future readers know why code is minimal.

### 4. Test Fixes Stay Local

Tests for local-specific code stay local. Don't try to upstream tests that only validate local patches.

### 5. Sync Regularly

```
λ sync(x).    fetch(origin) → log(HEAD..origin) → merge_or_rebase
              | review(changelog) → adapt(local_patches)
```

Check package updates, review changelogs, adapt local patches.

## Pattern

```
local = defensive_specific + edge_cases
upstream = general_core + happy_path
```

## Decision Matrix

| Change Type | Upstream PR | Local Patch | Rationale |
|-------------|-------------|-------------|-----------|
| Bug fixes (general) | ✅ Prefer | ❌ Avoid | Benefits all users |
| New features (general) | ✅ Prefer | ❌ Avoid | Maintainer decides scope |
| Security hardening | ✅ Prefer | ⚠️ Both | Upstream first, keep local until merged |
| Defensive workarounds | ❌ Avoid | ✅ Keep | Edge cases upstream won't prioritize |
| Project-specific logic | ❌ Never | ✅ Keep | Nucleus, mementum, custom tools |
| UI/UX customization | ❌ Avoid | ✅ Keep | Subjective preferences |

## Contribution Lambda

```
λ contribute(x).    general_fix(x) → PR(upstream)
                    | general_feature(x) → PR(upstream)
                    | edge_case(x) → local_patch
                    | project_specific(x) → local_only
                    | security(x) → PR(upstream) ∧ local_pending
```

## Sync Protocol

```
λ sync_cycle().    weekly → fetch(upstream) → review(changelog)
                    | breaking_change → adapt(local)
                    | feature_overlap → evaluate(keep_or_remove)
                    | commit(Δ) → note(upstream_version)
```

## Practical Rules

1. Bug in upstream? → PR first, local patch only if urgent and PR stalled
2. Missing feature? → PR proposal first, implement after discussion
3. Defensive workaround? → Keep local with clear commentary
4. Project-specific? → Never upstream, keep in `lisp/modules/`

## Ratio Target

```
70% upstream contributions (bugs, security, general improvements)
30% local patches (edge cases, defensive code, project-specific)
```

## Related

- `mementum/knowledge/project-facts.md` — architecture, modules
- `AGENTS.md` — `λ upstream(x)` rule

## Captured

2026-03-23 — From gptel-ext-fsm refactor verification

---

## PR Workflow Example (2026-03-23)

### Case: nil/null Tool Name Hangs FSM

**Discovery:** DashScope returns tool calls with nil/null function names, causing FSM to hang.

**Analysis:**
1. Found local fix in fork (`7a03645`)
2. Checked upstream — bug exists, no fix
3. Identified as general bug, not DashScope-specific

**PR Process:**

```bash
# 1. Create clean branch from upstream
git checkout -b fix-nil-tool-names upstream/master

# 2. Cherry-pick or re-implement minimal fix
#    (not the full defensive "invalid tool" pattern)
# 3. Commit with clear message
# 4. Push to fork
git push origin fix-nil-tool-names

# 5. Create PR against upstream
gh pr create --repo karthink/gptel --head davidwuchn:fix-nil-tool-names --base master
```

**Key Insight:**

```
λ pr_scope(x).    minimal_fix(x) > defensive_framework(x)
                  | clean_branch(upstream/master) > fork_branch(x)
                  | general_benefit(x) → PR(upstream)
                  | edge_case_only(x) → local_patch
```

**PR #1305:** https://github.com/karthink/gptel/pull/1305

### What We Did NOT Upstream

| Local Code | Reason |
|------------|--------|
| `my/gptel--sanitize-tool-calls` | Defensive pre-check, upstream handles in parser |
| `my/gptel--nil-tool-call-p` | Redundant with PR fix |
| "invalid" tool registration | Defensive fallback pattern |
| Doom-loop detection | Defensive, not a bug fix |

### Lesson

When local defensive code reveals an upstream bug:
1. **Extract the core fix** — minimal change to fix the bug
2. **Leave defensive layers local** — they may still be useful
3. **Don't upstream defensive frameworks** — maintainers prefer simple fixes

# Experiment Worktree Cleanup Pattern

**Pattern:** Merged experiment worktrees should be cleaned up to prevent accumulation.

**Symptoms:**
- Many stale worktrees in `var/tmp/experiments/`
- Experiment branches that were merged to staging but not deleted
- Worktree count grows without bound

**Detection:**
```bash
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

**Cleanup:**
```bash
git worktree remove <path> --force
git branch -D <branch>
```

**Prevention:**
- Auto-workflow should clean up merged experiments
- Periodic cleanup of merged worktrees
- Consider auto-deletion after merge to staging

**Example:** Cleaned 7 merged worktrees (agent-exp1, agent-exp2, core-exp2, strategic-exp1, strategic-exp2, tools-exp1, tools-exp2)

**Location:** `var/tmp/experiments/optimize/`