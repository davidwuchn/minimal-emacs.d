# Subagent Overlay Conflict

**Date**: 2026-03-29

**Problem**: Subagent overlays appearing in *Messages* buffer despite routing fixes.

**Root Cause**: TWO conflicting advices on `gptel-agent--task`:
1. `my/gptel-agent--task-override` with `:override` (old, line 461)
2. `gptel-auto-workflow--advice-task-override` with `:around` (new, in projects.el)

The old `:override` advice completely replaces the original function and creates overlays in `parent-buf`, which can be *Messages* if the FSM was created there.

**Symptoms**:
- Overlays still appear in *Messages* after "fixes"
- Executor and Grader overlays visible in wrong buffer
- "Buffer gptel.el modified; kill anyway?" prompts in headless mode

**Solution**:
1. Remove old `:override` advice
2. Merge caching logic into new `:around` advice
3. Add `kill-buffer` query suppression for headless mode

**Files**:
- `lisp/modules/gptel-tools-agent.el:461` - old advice registration
- `lisp/modules/gptel-auto-workflow-projects.el:212` - new advice

**Pattern**: Multiple advices on same function with different types (`:override` vs `:around`) causes unpredictable behavior. Use ONE advice type.