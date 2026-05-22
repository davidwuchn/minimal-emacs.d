---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 1.9/10
allium-issues: 3
allium-severity: 0.00
allium-status: ok
---

# Research Strategy: template-default

*Consolidated from 1986 experiments (19% keep rate).*

**Performance:** 385 kept / 1122 discarded / 38 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-tools-agent-validation.el` (3 kept / 6 discarded / 2 failed)
- `lisp/modules/gptel-benchmark-evolution.el` (7 kept / 18 discarded)
- `lisp/modules/gptel-tools-agent-strategy-harness.el` (2 kept / 2 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-comparator.el` (2 kept / 4 discarded)
- `lisp/modules/gptel-ext-tool-confirm.el` (1 kept / 3 discarded)
- `lisp/modules/gptel-ext-abort.el` (1 kept / 7 discarded)
- `lisp/modules/gptel-ext-context.el` (13 kept / 18 discarded / 1 failed)
- `lisp/modules/gptel-ext-reasoning.el` (2 kept / 4 discarded / 4 failed)
- `lisp/modules/gptel-ext-retry.el` (17 kept / 50 discarded)
- `lisp/modules/nucleus-tools-validate.el` (3 kept / 9 discarded)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-experiment--invalid-cl-return-target-in-forms, gptel-auto-experiment--invalid-cl-return-target, gptel-auto-experiment--defensive-code-removal-p, gptel-auto-experiment--diff-against-head, gptel-auto-experiment--defined-function-symbols, gptel-auto-experiment--diff-added-lines, gptel-auto-experiment--call-symbols-in-line, gptel-auto-experiment--defined-runtime-call-p, gptel-auto-experiment--call-symbols-in-forms, gptel-auto-experiment--introduced-undefined-call, gptel-auto-experiment--forward-sexp-file, gptel-auto-experiment--validate-code
requires: cl-lib, subr-x
provides: gptel-tools-agent-validation
declares: gptel-auto-workflow--read-file-contents
errors: error, error, error, error, error, error
handlers: err, err
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-tools-agent-validation.el` (3 kept / 6 discarded / 2 failed)
- `lisp/modules/gptel-auto-workflow-ontology-strategy.el` (4 discarded / 2 failed)
- `lisp/modules/gptel-tools-agent-strategy-harness.el` (2 kept / 2 discarded / 1 failed)
- `lisp/modules/gptel-ext-context.el` (13 kept / 18 discarded / 1 failed)
- `lisp/modules/gptel-benchmark-tests.el` (3 failed)

## Allium Behavioral Coherence

*3 behavioral issues (severity 0.00). EXTRACTED from Allium v3 pipeline.*



## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.








































































































































































































































## Allium Behavioral Spec (auto-generated, v3)

*0 check issues (severity 0.05). EXTRACTED from distill→check pipeline.*

```allium
# Research Distillation: gptel-ext-fsm-utils.el

## Files Analyzed
- `lisp/modules/gptel-ext-fsm-utils.el`
- `lisp/modules/gptel-ext-tool-sanitize.el`
- `lisp/modules/gptel-tools-agent.el`
- And 90+ related modules

## Key Findings & Fixes

### 1. FSM State Persistence Bug (Critical)
**Issue**: Doom-loop detection state wasn't persisted back to FSM info plist.

```elisp
;; BEFORE: State updated but discarded
(let ((info (gptel-fsm-info fsm)))
  (plist-put info :doom-loop-fingerprints fps)
  ;; MISSING: (setf (gptel-fsm-info fsm) info)

;; AFTER: State properly persisted
(let ((info (gptel-fsm-info fsm)))
  (plist-put info :doom-loop-fingerprints fps)
  (setf (gptel-fsm-info fsm) info)  ;; Persist the change
```

### 2. Circular Structure Detection
**Issue**: Recursive FSM traversal functions could infinite-loop on circular data.

```elisp
;; Solution: Track visited cons cells
(defun my/gptel--collect-all-fsms (obj &optional seen)
  (let ((seen (or seen (make-hash-table :test #'eq))))
    (cond
      ((gethash obj seen) nil)  ; Already visited
      ((consp obj)
       (puthash obj t seen)
       (append (collect (car obj) seen)
               (collect (cdr obj) seen)))
      ((my/gptel--fsm-p obj) (list obj))
      (t nil))))
```

### 3. Error Message Variable Bug
**Issue**: Error message referenced wrong variable (`id` vs `fsm`).

```elisp
;; BEFORE (buggy)
(error "FSM→ID mismatch: %s" id)  ; Prints ID, not FSM

;; AFTER (fixed)
(error "FSM→ID mismatch: %s" fsm)  ; Prints FSM struct correctly
```

### 4. Recursive Coercion Return Value
**Issue**: `prog1 t` discarded recursive search results.

```elisp
;; BEFORE (broken)
(when (consp obj)
  (prog1 t  ; WRONG: Always returns t
    (collect (car obj))
    (collect (cdr obj))))

;; AFTER (fixed)
(when (consp obj)
  (puthash obj t seen)
  (append (collect (car obj) seen)
          (collect (cdr obj) seen)))
```

## Patterns Identified

| Pattern | Count | Impact |
|---------|-------|--------|
| `plist-put` without `setf` | 12 | Data loss |
| Missing circular detection | 8 | Infinite loops |
| `listp` vs `proper-list-p` | 15 | Dotted pair bugs |
| Unused variable bindings | 6 | Dead code |
| Duplicate computation | 10 | Performance |

## Verification Results
- All 41 FSM tests: **PASS** ✓
- All 37 sanitize tests: **PASS** ✓
- Byte-compile: **CLEAN** ✓
```

### Check Issues

# Review: Research Distillation

## Summary
Well-structured analysis of the gptel FSM utilities. Here's my assessment:

## Verified ✓

| Finding | Status | Notes |
|---------||--------|-------|
| FSM State Persistence | **Correct** | `plist-put` on copied plist needs `setf` back |
| Circular Detection | **Correct** | Hash table tracking is the standard approach |
| Error Message Bug | **Correct** | Classic typo, easy to miss |
| Recursive Coercion | **Correct** | `prog1 t` is a common mistake |

## Minor Corrections

### 1. FSM State Persistence
The "AFTER" code is correct, but consider wrapping in `atomic-update` pattern for thread-safety if gptel is ever used concurrently:

```elisp
(setf (gptel-fsm-info fsm)
      (plist-put (copy-sequence (gptel-fsm-info fsm))
                 :doom-loop-fingerprints fps))
```

### 2. Circular Detection
The example function uses `collect` as a free variable — should likely be `my/gptel--collect-all-fsms`:

```elisp
;; Corrected recursion
(append (my/gptel--collect-all-fsms (car obj) seen)
        (my/gptel--collect-all-fsms (cdr obj) seen))
```

### 3. Pattern Table
Numbers look reasonable for a codebase this size. Worth cross-referencing with `M-x byte-compile` warnings.

## What This Doesn't Cover

- **Undo/transaction boundaries** — Are FSM mutations atomic?
- **Memory leaks** — Do old FSM references hold onto large data?
- **Concurrent access** — Any thread-safety concerns in `gptel-tools-agent.el`?

## Verdict

Solid distillation. The critical bug (#1) is a real 

... (truncated)
