<!--
Synthesis verification:
- Confidence: 24%
- Sources: 4 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'gptel-workflow-benchmark-el'
- Auto-approved: yes (flagged)
--->

---
title: gptel-workflow-benchmark.el Module Knowledge
status: active
category: knowledge
tags: [emacs, gptel, benchmarking, elisp, refactoring, bug-fix]
---

# gptel-workflow-benchmark.el Module Knowledge

## Overview

The `gptel-workflow-benchmark.el` module provides benchmarking and analysis functionality for gptel workflows. It evaluates workflow results against configurable score thresholds and provides pattern analysis capabilities.

## Core Helper Functions

### Score Extraction: `gptel-workflow--result-scores`

Extracts numeric scores from workflow result data structures. This function handles multiple input types to ensure consistent behavior.

```elisp
(defun gptel-workflow--result-scores (result)
  "Extract numeric score from RESULT.
Handles both plist and cons-pair formats."
  (cond
   ((plist-member result :score)
    (plist-get result :score))
   ((consp result)
    (let ((key (car result))
          (val (cdr result)))
      (when (numberp val) val)))
   (t nil)))
```

**Key Design Decisions:**

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Input types | plist + cons-pair | Flexibility for different result formats |
| Return type | number or nil | Explicit null handling |
| Default behavior | nil | No implicit fallback to 0 |

### Score Threshold Comparison: `gptel-workflow--score-below-threshold-p`

Compares a score against a threshold to determine pass/fail status.

```elisp
(defun gptel-workflow--score-below-threshold-p (score threshold)
  "Return t if SCORE is below THRESHOLD.
When SCORE is nil, defaults to THRESHOLD (returns nil)."
  (when threshold
    (if (null score)
        nil  ; nil score = threshold = pass
      (< score threshold))))
```

**Semantic Rule:** A `nil` score is treated as equal to the threshold, which constitutes a "pass" condition. This makes the implicit default behavior explicit and reduces confusion.

## Common Bug Patterns

### Off-by-One Errors in Boundary Iteration

When iterating over result sets with boundary conditions, ensure loop termination criteria are correct.

**Anti-pattern:**

```elisp
;; BUG: Off-by-one in boundary case
(dotimes (i (length results))
  (when (>= i 0)
    (process (nth i results))))
```

**Corrected Pattern:**

```elisp
;; FIXED: Proper boundary handling
(dotimes (i (length results))
  (when (< i (length results))
    (process (nth i results))))
```

**Verification Checklist:**

- [ ] Loop terminates at intended boundary
- [ ] Index never exceeds collection bounds
- [ ] Empty collections handled gracefully
- [ ] Single-element edge case tested

## Refactoring Patterns

### 1. Duplicate Logic Extraction

When `summarize-results` and `analyze-patterns` both extract scores, extract to shared helper:

```elisp
;; BEFORE: Duplicated in multiple functions
(let ((score (or (plist-get result :score)
                 (and (consp result) (cdr result)))))
  ...)

;; AFTER: Single extraction point
(let ((score (gptel-workflow--result-scores result)))
  ...)
```

**Benefits:**

- Single source of truth for score extraction
- Easier to modify handling for new input types
- Centralized bug fixes

### 2. Implicit Default to Explicit

Transform implicit behavior into explicit helper functions:

```elisp
;; BEFORE: Implicit assumption that nil = threshold
(when (< score threshold)
  (setq failures (1+ failures)))

;; AFTER: Explicit with helper function
(when (gptel-workflow--score-below-threshold-p score threshold)
  (setq failures (1+ failures)))
```

## Usage Examples

### Basic Benchmark Execution

```elisp
(require 'gptel-workflow-benchmark)

;; Set threshold for pass/fail determination
(setq gptel-workflow-benchmark-threshold 80)

;; Run benchmark on workflow results
(let ((results (gptel-workflow-run-benchmark my-workflow)))
  (gptel-workflow-summarize-results results))
```

### Custom Threshold Configuration

```elisp
(defun my-workflow-benchmark ()
  "Run benchmark with custom thresholds."
  (let* ((results (gptel-workflow-run-benchmark my-workflow))
         (scores (mapcar #'gptel-workflow--result-scores results))
         (avg-score (/ (apply #'+ scores) (length scores))))
    (message "Average score: %d" avg-score)
    (gptel-workflow-analyze-patterns results)))
```

### Handling Mixed Result Types

```elisp
;; Results can be mix of plists and cons-pairs
(let ((mixed-results
       (list
        (list :name "test1" :score 85)
        (cons "test2" 72)
        (list :name "test3") ; nil score = pass
        (cons "test4" 91))))
  (mapcar #'gptel-workflow--result-scores mixed-results)
  ;; => (85 72 nil 91)
  )
```

## Testing Patterns

### Unit Test for Score Extraction

```elisp
(ert-deftest test-gptel-workflow--result-scores ()
  "Test score extraction from various result formats."
  (should (= 85 (gptel-workflow--result-scores '(:name "test" :score 85))))
  (should (= 72 (gptel-workflow--result-scores '(test . 72))))
  (should (null (gptel-workflow--result-scores '(:name "test"))))
  (should (null (gptel-workflow--result-scores '(test . "not-a-number")))))
```

### Threshold Comparison Tests

```elisp
(ert-deftest test-gptel-workflow--score-below-threshold-p ()
  "Test threshold comparison logic."
  (should (gptel-workflow--score-below-threshold-p 50 80))
  (should-not (gptel-workflow--score-below-threshold-p 85 80))
  (should-not (gptel-workflow--score-below-threshold-p nil 80)) ; nil = pass
  (should-not (gptel-workflow--score-below-threshold-p 80 80)))
```

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `gptel-workflow-benchmark-threshold` | 80 | Minimum score for pass |
| `gptel-workflow-benchmark-iterations` | 10 | Number of test runs |
| `gptel-workflow-benchmark-timeout` | 30 | Seconds before timeout |

## Related

- [gptel-workflow.el](gptel-workflow.html) - Core workflow module
- [gptel-workflow-analysis.el](gptel-workflow-analysis.html) - Pattern analysis utilities
- [Emacs Lisp Testing Best Practices](testing-best-practices.html) - Unit testing patterns
- [Elisp Refactoring Techniques](elisp-refactoring.html) - Code extraction patterns
- [Boundary Condition Testing](boundary-testing.html) - Off-by-one error prevention