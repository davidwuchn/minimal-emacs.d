## Early-Return TSV Logging Fix (2026-06-02)

### Problem
Results.tsv files were often empty (header-only) despite 870+ experiments running. Root cause: early return paths in `gptel-auto-experiment-run` called the callback but skipped TSV logging.

### Affected Paths (gptel-tools-agent-experiment-core.el)
1. **Quota exhaustion** (line ~189): Returned before let* block where log-fn defined
2. **Executor callback missing** (line ~273): Inside launch-executor lambda
3. **Executor prompt empty** (line ~288): Inside launch-executor lambda  
4. **Precondition error** (line ~359): Inside launch-executor lambda
5. **Worktree creation failed** (line ~374): Outside let* block

### Fix Pattern
```elisp
(let ((error-result (list :target target :id experiment-id :kept nil ...)))
  ;; ASSUMPTION: Early returns must log to TSV for accurate tracking
  (funcall log-fn run-id error-result)  ;; or gptel-auto-experiment-log-tsv directly
  (when (functionp callback)
    (funcall callback error-result)))
```

### Key Insight
For paths outside the let* block (quota exhaustion, worktree failure), use `gptel-auto-workflow--run-id` directly with guard: `(when (and (boundp 'gptel-auto-workflow--run-id) gptel-auto-workflow--run-id) ...)`.

### Evidence
Before fix: Many results.tsv had only 1 line (header)
After fix: All experiment outcomes logged, enabling accurate frontier analysis and strategy evolution