---
title: Pattern Knowledge Page
status: active
category: knowledge
tags: [pattern, elisp, emacs, buffer-local, fsm, scheduling, workflow, anti-pattern]
---

# Pattern Knowledge Page

This knowledge page catalogs actionable patterns and anti-patterns discovered through the auto-workflow development process. Each entry provides concrete implementation guidance, code examples, and cross-references to related patterns.

---

## Overview

| Pattern | Category | Status |
|---------|----------|--------|
| Buffer-Local Variable | Core | ✅ Active |
| Cron-Based Scheduling | Infrastructure | ✅ Active |
| FSM Creation | Auto-Workflow | ✅ Active |
| LLM-Generated Syntax Error | Anti-Pattern | ⚠️ Detection |
| Module Load Order | Core | ✅ Active |
| Nested Defun | Anti-Pattern | ⚠️ Detection |
| Nil Guard | Core | ✅ Active |
| Upstream Cooperation | Workflow | ✅ Active |
| Experiment Cleanup | Infrastructure | ✅ Active |

---

## Buffer-Local Variable Pattern

### Description

Buffer-local variables must be set in the correct buffer context. Mixing buffer contexts leads to variables being nil in unexpected places or overwriting values in wrong buffers.

### Problem

```elisp
;; WRONG - sets in current buffer, not target
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local, affects wrong buffer
(setq-local gptel--fsm-last fsm)  ; in wrong buffer
```

### Solution

```elisp
;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or create in current buffer if that's correct context
(setq-local gptel--fsm-last fsm)  ; in correct buffer
```

### Common Buffer-Local Variables

| Variable | Purpose |
|----------|---------|
| `gptel--fsm-last` | FSM state for conversation |
| `gptel-backend` | LLM backend configuration |
| `gptel-model` | Model name |
| `gptel--stream-buffer` | Response buffer for streaming |

### Signal

- Variable is nil unexpectedly → check buffer context
- Variable works in some buffers but not others → buffer-local issue
- Use `with-current-buffer` to ensure correct context

### Test

```elisp
(with-current-buffer target
  (should gptel--fsm-last))  ; Verify set in correct buffer
```

### Related

- [FSM Creation Pattern](#fsm-creation-pattern)
- [Module Load Order Pattern](#module-load-order-pattern)

---

## Cron-Based Scheduling for Emacs

### Description

Use cron for scheduled Emacs tasks instead of Emacs timers for tasks that need to survive restarts and follow standard Unix patterns.

### Why Cron Over Emacs Timers

| Aspect | Cron | Emacs Timer |
|--------|------|-------------|
| Survives restart | ✅ Yes | ❌ No |
| Standard Unix | ✅ Yes | Emacs-specific |
| Log management | ✅ Easy | Manual |
| Visibility | ✅ `crontab -l` | Inside Emacs |
| Session-aware | ❌ No | ✅ Yes |

### Implementation

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

### Related

- [Experiment Cleanup Pattern](#experiment-worktree-cleanup-pattern)
- [FSM Creation Pattern](#fsm-creation-pattern)

---

## FSM Creation Pattern for Auto-Workflow

### Description

When creating fresh worktree buffers for auto-workflow experiments, the FSM must be explicitly created since `gptel-request` is never called.

### Problem

`gptel-agent--task` accesses `gptel--fsm-last` which is nil in fresh worktree buffers.

**Error**: `Wrong type argument: gptel-fsm, nil`

### Root Cause

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

### Solution

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

### Signal

- Agent tasks need FSM in buffer
- FSM is buffer-local variable
- Create FSM before calling agent functions

### Verification

Evidence of success:
```
[FSM-DEBUG] fsm-last before: #s(gptel-fsm INIT ...)
[nucleus] Subagent executor still running... (596.7s elapsed)
```

### Related

- [Buffer-Local Variable Pattern](#buffer-local-variable-pattern)
- [Module Load Order Pattern](#module-load-order-pattern)

---

## LLM-Generated Syntax Error Pattern (Anti-Pattern)

### Description

LLM-generated commits can introduce syntax errors while claiming to fix them. This anti-pattern documents detection and prevention strategies.

### Example

**Commit**: 36bccd28
**Message**: "fix: Correct parentheses balance"
**Claim**: "EVIDENCE: File loads successfully"

**Reality**: Added EXTRA closing paren → syntax error

```diff
-          :analysis-timestamp (format-time-string "%Y-%m-%dT%Y-%m-%dT%H:%M:%S"))))
+          :analysis-timestamp (format-time-string "%Y-%m-%dT%Y-%m-%dT%H:%M:%S")))))
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

### Related

- [Module Load Order Pattern](#module-load-order-pattern)
- [Nested Defun Anti-Pattern](#nested-defun-anti-pattern)

---

## Module Load Order Pattern

### Description

Require modules before using their variables/functions. Load order matters in Elisp, especially with cross-file dependencies.

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

#### 1. Forward Declaration

```elisp
(defvar gptel--tool-preview-alist nil)  ; Forward declare
```

#### 2. Require Dependencies

```elisp
(require 'gptel-request)
(require 'gptel-agent-tools)
```

#### 3. Ensure Correct Load Order

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
- Function works interactively but not programmatically → load order
- Works after manual require → missing dependency

### Best Practice

1. Use `require` for dependencies
2. Forward declare variables from other files
3. Document dependencies in comments
4. Test in clean Emacs instance

### Related

- [FSM Creation Pattern](#fsm-creation-pattern)
- [Nil Guard Pattern](#nil-guard-pattern)

---

## Nested Defun Anti-Pattern

### Description

Nested `defun` inside another function is an anti-pattern that creates new function objects on every call and makes the function inaccessible from outside.

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

### Related

- File: `lisp/modules/gptel-workflow-benchmark.el:709`
- Fix: commit `25c63eb` then `9056845`

---

## Nil Guard Pattern for Elisp

### Description

Guard nil values before passing to functions expecting number-or-marker. Elisp functions like `=`, `make-overlay`, `copy-marker` throw `wrong-type-argument` when passed nil.

### Problem

This crashes in process sentinels and FSM callbacks where edge cases (curl timeout, missing FSM info) can produce nil values.

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

| File | Line | Pattern |
|------|------|---------|
| `gptel-tools-agent.el` | 133-137 | marker fallback chain |
| `gptel-agent-loop.el` | 506-512 | same pattern |
| `gptel-ext-tool-confirm.el` | 337-340 | tool confirm guard |
| `gptel-ext-retry.el` | 314-318 | `(numberp status)` guard |

### Commits

- `57d96ab` — FSM markers nil
- `aa4e5e8` — HTTP status nil

### Related

- [FSM Creation Pattern](#fsm-creation-pattern)
- [Buffer-Local Variable Pattern](#buffer-local-variable-pattern)

---

## Upstream Cooperation Pattern

### Description

Guidelines for maintaining a fork with local patches that overlap with upstream functionality.

### Core Principles

#### 1. Verify Before Removing

```
λ upstream(x).    claim(x) → verify(grep, sed, read)
                   | upstream_has(x) → safe_remove(local)
                   | ¬upstream_has(x) → keep(local)
```

Don't trust commit messages alone. Verify functions exist in upstream code.

**Example**: Verified `gptel--update-wait` in `gptel.el:1180`, `gptel--handle-error` in `gptel.el:1349` before removing local equivalents.

#### 2. Keep Defensive Workarounds

Upstream focuses on happy path. Local code should keep:
- Edge case handlers upstream doesn't cover
- Defensive safety nets
- Error recovery for corrupted state

**Example**: Kept `my/gptel--recover-fsm-on-error` (error+STOP limbo) and subagent error logging—upstream doesn't have these.

#### 3. Commentary as Migration Log

Document what moved where in file header:

```elisp
;;; Commentary:
;; Defensive workarounds for gptel FSM edge cases.
;; Core FSM fixes are now in gptel-agent-tools.el:
;; - Stuck FSM fix (gptel--fix-stuck-fsm)
;; - Error display fix (gptel-agent--fix-error-display)
```

#### 4. Test Fixes Stay Local

Tests for local-specific code stay local. Don't try to upstream tests that only validate local patches.

#### 5. Sync Regularly

```
λ sync(x).    fetch(origin) → log(HEAD..origin) → merge_or_rebase
              | review(changelog) → adapt(local_patches)
```

### Pattern

```
local = defensive_specific + edge_cases
upstream = general_core + happy_path
```

### Decision Matrix

| Change Type | Upstream PR | Local Patch | Rationale |
|------------|-------------|-------------|-----------|
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

### PR Workflow

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

### What We Did NOT Upstream

| Local Code | Reason |
|------------|--------|
| `my/gptel--sanitize-tool-calls` | Defensive pre-check, upstream handles in parser |
| `my/gptel--nil-tool-call-p` | Redundant with PR fix |
| "invalid" tool registration | Defensive fallback pattern |
| Doom-loop detection | Defensive, not a bug fix |

### Related

- [Module Load Order Pattern](#module-load-order-pattern)
- [LLM-Generated Syntax Error Pattern](#llm-generated-syntax-error-pattern-anti-pattern)

---

## Experiment Worktree Cleanup Pattern

### Description

Merged experiment worktrees should be cleaned up to prevent accumulation. Stale worktrees consume resources and create confusion.

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

**Location**: `var/tmp/experiments/optimize/`

### Related

- [Cron-Based Scheduling](#cron-based-scheduling-for-emacs)

---

## Cross-Reference Matrix

| Pattern | Related Topics |
|---------|----------------|
| Buffer-Local Variable | FSM Creation, Nil Guard |
| Cron-Based Scheduling | Experiment Cleanup |
| FSM Creation | Buffer-Local, Module Load Order |
| LLM-Generated Syntax Error | Module Load Order, Nested Defun |
| Module Load Order | FSM Creation, Buffer-Local |
| Nested Defun | LLM-Generated Syntax Error |
| Nil Guard | FSM Creation, Buffer-Local |
| Upstream Cooperation | Module Load Order, LLM-Generated Syntax Error |
| Experiment Cleanup | Cron-Based Scheduling |

---

## Pattern Decision Flowchart

```
                    ┌─────────────────┐
                    │  Need to add    │
                    │  new code?      │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
        ┌─────────────┐               ┌─────────────┐
        │ General    │               │ Project    │
        │ feature?  │               │ specific?  │
        └─────┬─────┘               └─────┬─────┘
              │                             │
     ┌────────┴────────┐         ┌────────┴────────┐
     ▼                 ▼         ▼                  ▼
┌─────────┐      ┌─────────┐ ┌─────────┐      ┌─────────┐
│ Bug fix │      │ Feature │ │ Keep    │      │ Keep    │
│?        │      │?        │ │ local   │      │ local   │
└────┬────┘      └────┬────┘ └────┬────┘      └────┬────┘
     │                 │          │                 │
     ▼                 ▼          ▼                 ▼
┌─────────┐      ┌─────────┐ ┌─────────┐      ┌─────────┐
│ PR to    │      │ Propose  │ │ No PR   │      │ No PR   │
│ upstream│      │ upstream│ │ needed  │      │ needed  │
└─────────┘      └─────────┘ └─────────┘      └─────────┘
```

---

## Quick Reference Commands

### Check Buffer Context

```elisp
(current-buffer)           ; Get current buffer
(with-current-buffer BUF    ; Execute in buffer context
  ...)
(buffer-local-value VAR BUF ; Get buffer-local value
```

### Verify Load Order

```elisp
(require 'gptel-request)  ; Require with error if missing
(featurep 'gptel)         ; Check if loaded
```

### Syntax Check

```elisp
emacs -Q --batch -l my.el  ; Load and check syntax
forward-sexp              ; Check parentheses
```

### Worktree Management

```bash
git worktree list           ; List all worktrees
git worktree add <path> <branch>  ; Add worktree
git worktree remove <path> --force ; Remove worktree
```

---

## Related

- [Knowledge: Auto-Workflow](auto-workflow.md)
- [Knowledge: Project Facts](project-facts.md)
- [Knowledge: FSM Architecture](fsm.md)
- [AGENTS.md](../AGENTS.md) — `λ upstream(x)` rule

---

*This knowledge page is maintained as part of the auto-workflow system and updated as new patterns are discovered.*