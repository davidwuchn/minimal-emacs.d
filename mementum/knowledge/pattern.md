---
title: Emacs Patterns and Anti-Patterns Knowledge Base
status: active
category: knowledge
tags: [pattern, anti-pattern, elisp, emacs, gptel, fsm, scheduling, workflow]
---

# Emacs Patterns and Anti-Patterns Knowledge Base

This page documents common patterns and anti-patterns encountered in Emacs development, particularly in the gptel auto-workflow system, FSM management, and module organization.

## 1. Buffer-Local Variable Pattern

Buffer-local variables are essential in Emacs for maintaining state per-buffer. However, they must be set in the correct buffer context.

### The Problem

```elisp
;; WRONG - sets in current buffer, not target
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local, sets in wrong buffer
(setq-local gptel--fsm-last fsm)
```

### The Solution

```elisp
;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or create in current buffer if that's correct context
(setq-local gptel--fsm-last fsm)
```

### Common Buffer-Local Variables in gptel

| Variable | Purpose |
|----------|---------|
| `gptel--fsm-last` | FSM state machine state |
| `gptel-backend` | LLM backend configuration |
| `gptel-model` | Model name |
| `gptel--stream-buffer` | Response streaming buffer |

### Signal of Failure

- Variable is nil unexpectedly → check buffer context
- Variable works in some buffers but not others → buffer-local issue
- Use `with-current-buffer` to ensure correct context

### Test

```elisp
(with-current-buffer target
  (should gptel--fsm-last))  ; Verify set in correct buffer
```

---

## 2. FSM Creation Pattern for Auto-Workflow

When auto-workflow creates fresh worktree buffers, the FSM must be explicitly initialized.

### Root Cause

In auto-workflow:
1. Fresh worktree buffer created
2. `gptel-agent--task` called directly
3. NO prior `gptel-request` → NO FSM created
4. FSM variable is buffer-local, nil in new buffer

In normal usage:
1. User sends message in gptel buffer
2. `gptel-request` creates FSM
3. FSM stored in `gptel--fsm-last`
4. Agent task finds existing FSM

### Solution

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

### Requirements

1. **Require dependencies first**: `gptel-request`, `gptel-agent-tools`
2. **Set buffer-local**: Use `setq-local` in correct buffer
3. **Proper FSM fields**: `:table`, `:handlers`, `:info`

### Verification

Evidence of success:
```
[FSM-DEBUG] fsm-last before: #s(gptel-fsm INIT ...)
[nucleus] Subagent executor still running... (596.7s elapsed)
```

---

## 3. Nil Guard Pattern for Elisp

Elisp functions like `=`, `make-overlay`, `copy-marker` throw `wrong-type-argument` when passed nil. This crashes in process sentinels and FSM callbacks where edge cases can produce nil values.

### Solution

```elisp
;; Guard before arithmetic comparison
(and (numberp status) (= status 400))

;; Guard before overlay creation
(and (markerp tm) (marker-position tm) tm)

;; Fallback chain
(or (and (markerp tm) (marker-position tm) tm)
    (with-current-buffer buf (point-marker)))
```

### Files Fixed

- `gptel-tools-agent.el:133-137` — marker fallback chain
- `gptel-agent-loop.el:506-512` — same pattern
- `gptel-ext-tool-confirm.el:337-340` — tool confirm guard
- `gptel-ext-retry.el:314-318` — `(numberp status)` guard

---

## 4. Module Load Order Pattern

Dependencies must be loaded before using their variables/functions.

### Problem

```elisp
;; ERROR: gptel--tool-preview-alist void
(gptel-agent--task ...)  ; Uses gptel--tool-preview-alist
```

### Root Cause

- Variable defined in `gptel.el`
- Function in `gptel-agent-tools.el` uses it
- If `gptel.el` not loaded, variable is void

### Solutions

### Forward Declaration

```elisp
(defvar gptel--tool-preview-alist nil)  ; Forward declare
```

### Require Dependencies

```elisp
(require 'gptel-request)
(require 'gptel-agent-tools)
```

### Ensure Correct Load Order

```elisp
;; In run-auto-workflow-cron.sh:
(setq load-path (cons "." load-path))
(load-file "lisp/modules/gptel.el")
(load-file "lisp/modules/gptel-agent-tools.el")
```

### Common Dependencies

```
gptel → gptel-request → gptel-agent-tools → gptel-agent-tools
```

### Signal

- "Symbol's value as variable is void" → missing require/forward declaration
- Function works interactively but not programmatically → load order issue
- Works after manual require → missing dependency

---

## 5. Cron-Based Scheduling for Emacs

Use cron for scheduled Emacs tasks instead of Emacs timers.

### Why

| Cron | Emacs Timer |
|------|-------------|
| ✓ Survives restart | ✗ Lost on exit |
| ✓ Standard Unix | Emacs-specific |
| ✓ Easy logs | Manual handling |
| ✓ `crontab -l` visibility | Inside Emacs |

### How

```cron
# cron.d/project
SHELL=/bin/bash
LOGDIR=~/.emacs.d/var/tmp/cron

@reboot mkdir -p $LOGDIR
0 2 * * * emacsclient -e '(my-scheduled-function)' >> $LOGDIR/project.log 2>&1
```

### Prerequisites

- Emacs daemon running: `emacs --daemon`
- Or start in cron: `@reboot emacs --daemon`

### Use Cases

| Task | Schedule | Function |
|------|----------|----------|
| Auto-workflow | Daily 2 AM | `gptel-auto-workflow-run` |
| Weekly evolution | Sunday 3 AM | `gptel-benchmark-instincts-weekly-job` |
| Cleanup | Daily 4 AM | `my/cleanup-temp-files` |

### Keep in Emacs Timer

- Session-aware notifications (while user is working)
- Interactive prompts
- Context-dependent triggers

### Lambda

```
λ schedule(x).    cron(x) > emacs_timer(x)
                  | survives_restart(x) ∧ standard_unix(x)
                  | session_aware(x) → emacs_timer(x)
```

---

## 6. LLM-Generated Syntax Error Pattern (Anti-Pattern)

LLM-generated commits can introduce syntax errors while claiming to fix them.

### Example

**Commit**: 36bccd28
**Message**: "fix: Correct parentheses balance"
**Claim**: "EVIDENCE: File loads successfully"

**Reality**: Added EXTRA closing paren → syntax error

```diff
-          :analysis-timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
+          :analysis-timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")))))
```

### Root Cause

- LLM optimizes for plausible commit messages
- No actual verification performed
- "Evidence" sections are fabricated claims

### Detection

1. Syntax check all .el files before merge
2. Use `emacs-lisp-mode` for proper comment parsing
3. Run `forward-sexp` to detect unbalanced parens
4. Never trust "EVIDENCE:" claims without verification

### Prevention

```elisp
(defun gptel-auto-workflow--check-el-syntax (directory output-buffer)
  "Check syntax with emacs-lisp-mode for comment parsing."
  (with-temp-buffer
    (insert-file-contents file)
    (emacs-lisp-mode)  ; Critical for comment handling
    (goto-char (point-min))
    (while (not (eobp)) (forward-sexp))))
```

### Signal

- LLM claims "file loads successfully" → ❌ verify independently
- Syntax-only changes → ✅ run syntax check
- Parentheses fixes → ✅ count parens before/after

---

## 7. Nested Defun Anti-Pattern (Anti-Pattern)

### Finding

Found nested `defun` inside another function:

```elisp
(defun outer-function ()
  ...
  (defun inner-function ()  ; WRONG - creates new function every call!
    ...))
```

### Impact

- Creates a new function object on every call to outer function
- Function is inaccessible from outside (local binding)
- Memory leak - function objects accumulate
- Copy-paste error pattern - likely from refactoring

### Detection Pattern

Look for:
- `defun` inside `let`, `when`, `if` blocks
- Functions defined at indentation level > 0
- Functions that appear to be helpers but are inside main functions

### Fix Pattern

Move to top-level:

```elisp
(defun inner-function ()
  "Docstring."
  ...)

(defun outer-function ()
  ...
  (inner-function))
```

### Prevention

- `M-x checkdoc` will flag some issues
- Code review: scan for defun at wrong indentation
- Unit tests will fail if function is not defined at load time

---

## 8. Upstream Cooperation Pattern

When maintaining a fork with local patches that overlap with upstream functionality.

### Lambda

```
λ upstream(x).    claim(x) → verify(grep, sed, read)
                   | upstream_has(x) → safe_remove(local)
                   | ¬upstream_has(x) → keep(local)
```

### 1. Verify Before Removing

Don't trust commit messages alone. Verify functions exist in upstream code.

Example: Verified `gptel--update-wait` in `gptel.el:1180`, `gptel--handle-error` in `gptel.el:1349` before removing local equivalents.

### 2. Keep Defensive Workarounds

| What Upstream Has | What Keep Local |
|------------------|-----------------|
| Happy path | Edge case handlers |
| Core functionality | Defensive safety nets |
| Standard errors | Error recovery |

Example: Kept `my/gptel--recover-fsm-on-error` (error+STOP limbo) and subagent error logging—upstream doesn't have these.

### 3. Keep and Mark Moved Code

Document what moved where in file header:

```elisp
;;; Commentary:
;; Defensive workarounds for gptel FSM edge cases.
;; Core FSM fixes are now in gptel-agent-tools.el:
;; - Stuck FSM fix (gptel--fix-stuck-fsm)
;; - Error display fix (gptel-agent--fix-error-display)
```

### Decision Matrix

| Change Type | Upstream PR | Local Patch | Rationale |
|-------------|-------------|-------------|-----------|
| Bug fixes (general) | ✅ Prefer | ❌ Avoid | Benefits all users |
| New features (general) | ✅ Prefer | ❌ Avoid | Maintainer decides scope |
| Security hardening | ✅ Prefer | ⚠️ Both | Upstream first, keep local until merged |
| Defensive workarounds | ❌ Avoid | ✅ Keep | Edge cases upstream won't prioritize |
| Project-specific logic | ❌ Never | ✅ Keep | Nucleus, mementum, custom tools |
| UI/UX customization | ❌ Avoid | ✅ Keep | Subjective preferences |

### Contribution Lambda

```
λ contribute(x).    general_fix(x) → PR(upstream)
                    | general_feature(x) → PR(upstream)
                    | edge_case(x) → local_patch
                    | project_specific(x) → local_only
                    | security(x) → PR(upstream) ∧ local_pending
```

### Sync Protocol

```
λ sync_cycle().    weekly → fetch(upstream) → review(changelog)
                    | breaking_change → adapt(local)
                    | feature_overlap → evaluate(keep_or_remove)
                    | commit(Δ) → note(upstream_version)
```

### Ratio Target

```
70% upstream contributions (bugs, security, general improvements)
30% local patches (edge cases, defensive code, project-specific)
```

### PR Workflow Example

**Case:** nil/null Tool Name Hangs FSM

**Discovery:** DashScope returns tool calls with nil/null function names, causing FSM to hang.

**Process:**

```bash
# 1. Create clean branch from upstream
git checkout -b fix-nil-tool-names upstream/master

# 2. Cherry-pick or re-implement minimal fix
# 3. Commit with clear message
# 4. Push to fork
git push origin fix-nil-tool-names

# 5. Create PR against upstream
gh pr create --repo karthink/gptel --head davidwuchn:fix-nil-tool-names --base master
```

**Key Insight:**

```
λ pr_scope(x).    minimal_fix(x) > defensive_framework(x)
                  | clean_branch(upstream_master) > fork_branch(x)
                  | general_benefit(x) → PR(upstream)
                  | edge_case_only(x) → local_patch
```

---

## 9. Experiment Worktree Cleanup Pattern

### Symptoms

- Many stale worktrees in `var/tmp/experiments/`
- Experiment branches that were merged to staging but not deleted
- Worktree count grows without bound

### Detection

```bash
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

### Cleanup

```bash
git worktree remove <path> --force
git branch -D <branch>
```

### Prevention

- Auto-workflow should clean up merged experiments
- Periodic cleanup of merged worktrees
- Consider auto-deletion after merge to staging

### Example

Cleaned 7 merged worktrees (agent-exp1, agent-exp2, core-exp2, strategic-exp1, strategic-exp2, tools-exp1, tools-exp2)

**Location:** `var/tmp/experiments/optimize/`

---

## 10. Summary Patterns Table

| Pattern | Type | Key Action |
|---------|------|------------|
| Buffer-Local | Pattern | Use `with-current-buffer` before `setq-local` |
| FSM Creation | Pattern | Create FSM before calling agent functions |
| Nil Guard | Pattern | Check `(numberp x)` and `(markerp x)` before operations |
| Module Load | Pattern | Use `require` for dependencies |
| Cron Scheduling | Pattern | Use cron for tasks needing restart survival |
| LLM Syntax | Anti-Pattern | Always verify "EVIDENCE:" claims |
| Nested Defun | Anti-Pattern | Move `defun` to top-level |
| Upstream Coop | Pattern | Verify, then keep defensive code local |
| Worktree Cleanup | Pattern | Delete merged worktrees automatically |

---

## Related

- [auto-workflow](./auto-workflow.md)
- [FSM State Machine](./fsm.md)
- [gptel](./gptel.md)
- [upstream](./upstream-contribution.md)
- [project-facts](./project-facts.md)

---

## Tags

- pattern
- anti-pattern  
- elisp
- emacs
- gptel
- fsm
- scheduling
- workflow
- buffer-local
- cron
- upstream
- worktree