# Auto-Workflow E2E Bug: Deleted Buffer

**Discovery:** During e2e test, auto-workflow fails with "Selecting deleted buffer" error.

**Symptoms:**
- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution
- Executor runs for 560s+ without completing changes
- No results logged to TSV file
- Error: `gptel callback error: (error "Selecting deleted buffer")`

**Root Cause:**
The `gptel-auto-workflow--advice-task-override` advice overrides `current-buffer` to return a fixed project buffer. If that buffer is killed during async execution, all callbacks fail.

**Fix Applied:**
1. Added `kill-buffer-query-functions` protection to prevent buffer kill during runs
2. Made `current-buffer` override check liveness each call, fall back if killed
3. Saved original `current-buffer` function before overriding to avoid recursion

**Result:**
- E2E test passed - experiment completed in 230s with `kept` decision
- Score improved: 0.40 → 0.41
- Commit `bae1b73` merged to staging

**Symbol:** ✅ (fixed)