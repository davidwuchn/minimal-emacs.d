# Mementum State

> Last session: 2026-03-24

## Recent Learning 🔁

**Systematic Code Review Strategy**

Single-file optimization is limited. Better approach:

```
scan entire repo → categorize issues → prioritize → fix systematically
```

### Issue Categories (by severity)

| Priority | Category | Detection |
|----------|----------|-----------|
| Critical | Duplicate functions | `grep "(defun" | sort | uniq -c` |
| High | Unused variables | `byte-compile` warnings |
| Medium | Docstring width >80 | `byte-compile` warnings |
| Medium | Wrong quote usage | `byte-compile` warnings |
| Low | Missing declare-function | `byte-compile` warnings |

### Results This Session

| Before | After |
|--------|-------|
| ~20 warnings | 1 warning (false positive) |
| 2 duplicate functions | 0 |
| 7 unused variables | 0 |
| 8 wide docstrings | 0 |
| 4 wrong quotes | 0 |

### Commit

`5ff621d` - Δ fix code quality issues: duplicates, unused vars, docstrings

## Built ✓

**Auto-Experiment with Real Quality Scoring**

### Quality Scoring System

```
Score = 1.0 - (checkdoc_issues × 0.01 + missing_docs × 0.005)
```

| Metric | Weight | Detection |
|--------|--------|-----------|
| Checkdoc issues | -0.01 each | `checkdoc-current-buffer` |
| Missing docstrings | -0.005 each | Regex `(defun X)` without following `"` |

### Feed-Forward Learning (Mementum)

When experiment improves score > 0.02:
1. Store to `mementum/memories/auto-exp-{file}-{timestamp}.md`
2. Commit with symbol: `💡 {slug}: +{delta} quality score`
3. Recall past learnings for same file on next run

### Prompt Improvements

- Shows file analysis (lines, functions, undocumented count)
- Shows past successful improvements from git history
- Clearer objective: ONE specific improvement

### Test Commands

```elisp
;; Check quality score of a file
(setq gptel-auto-workflow--current-target "lisp/modules/gptel-ext-retry.el")
(gptel-auto-experiment--quality-score)

;; Run auto-experiment
(setq gptel-auto-experiment-lite-mode t)
(gptel-auto-workflow-run '("lisp/modules/gptel-ext-retry.el"))
```

### How It Works

1. Baseline: Compute quality score (undocumented functions, checkdoc issues)
2. Experiment: Agent makes ONE targeted improvement
3. Benchmark: Re-compute quality score
4. Decide: Keep if score improved
5. Learn: Store successful patterns to mementum
6. Repeat: Next experiment sees past learnings

### Feed-Forward Cycle

```
experiment → improvement → score ↑ → store to mementum
                                          ↓
next experiment ← recall from git ← commit
```

This creates compound learning across sessions.