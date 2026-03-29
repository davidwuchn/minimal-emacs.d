# Auto-Workflow E2E Bug: Deleted Buffer

**Discovery:** During e2e test, auto-workflow fails with "Selecting deleted buffer" error.

**Symptoms:**
- Project buffer `*gptel-agent:.emacs.d*` gets deleted during execution
- Executor runs for 560s+ without completing changes
- No results logged to TSV file
- Error: `gptel callback error: (error "Selecting deleted buffer")`

**Root Cause:**
The `gptel-auto-workflow--advice-task-override` advice tries to access the project buffer after it's been killed. The buffer management in multi-project mode needs fixing.

**Location:**
- `gptel-auto-workflow-projects.el:gptel-auto-workflow--advice-task-override`
- The `(lambda () project-buf)` override for `current-buffer` causes issues when buffer is deleted

**Fix Needed:**
1. Check buffer liveness before routing to project buffer
2. Fall back to current buffer if project buffer is dead
3. Ensure project buffer persists throughout experiment

**Symbol:** ❌