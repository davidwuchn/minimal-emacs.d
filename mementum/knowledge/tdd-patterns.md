# TDD Patterns for Elisp

## Status: active

## Related

- tdd-first-methodology.md
- tdd-test-helper-sync.md
- surgical-edits-nested-code.md
- test-isolation-issue.md
- auto-workflow-branching.md

## Content

### Core TDD Cycle

```
1. Write failing test
2. Run test (verify failure)
3. Write minimal code to pass
4. Run test (verify pass)
5. Refactor if needed
```

### Pattern 1: Test Helper Sync

Test helpers must match real implementation. When test fails:
1. Check if test expectation is correct
2. Check if test helper matches real code
3. Fix whichever is wrong

Example: `exit code 28` pattern detection - test helper didn't match real regex.

### Pattern 2: Surgical Edits

For deeply nested code (>5 levels):
1. Make minimal edits - only change what needs changing
2. Edit beginning first, then end
3. Verify after each edit with `emacs --batch -l file.el`

### Pattern 3: Test Isolation

Tests pass in isolation but fail together when:
1. Global state pollution between tests
2. Mock functions overwrite each other
3. Advice persists across tests
4. `require` order affects definitions

### Pattern 4: Auto-Workflow Sync Testing (NEW 2026-03-25)

**Problem**: Async functions return immediately when called via `emacsclient -e`

**Root Cause**: `emacsclient -e` exits event loop before async callbacks fire

**Solution**: Use `accept-process-output` to keep event loop alive:

```elisp
(defun my-run-sync ()
  (let ((running t))
    (my-run-async (lambda () (setq running nil)))
    (while running
      (accept-process-output nil 1.0))))
```

**Pattern**:
```
λ sync-wrapper(async-fn).
    let(running=t) → async-fn(λ running=nil)
    | while(running) → accept-process-output(nil 1.0)
```

### Pattern 5: Agent Prompt Context (NEW 2026-03-25)

**Problem**: LLM agents return errors when asked to edit files

**Root Cause**: Prompt lacks working directory and full target path

**Solution**: Always include in prompt:
1. Working directory (absolute path)
2. Target file (absolute path)
3. Explicit instruction to use full paths with tools

**Example**:
```
## Working Directory
/Users/davidwu/.emacs.d

## Target File (full path)
/Users/davidwu/.emacs.d/lisp/modules/target.el

## Instructions
1. Read the target file using its full path
2. Edit the file using the full path
```

### Pattern 6: Auto-Workflow Branching (NEW 2026-03-25)

**Rule**: Auto-workflow changes must NEVER push to main directly

**Branch Format**: `optimize/{target}-{hostname}-exp{N}`

**Flow**:
1. Create worktree with optimize branch
2. Executor makes changes in worktree
3. If improvement → commit to optimize branch
4. Push to `origin optimize/...` (NOT main!)
5. Human reviews and merges to main

**Why**:
- Prevents unreviewed AI changes on main
- Multiple machines can optimize same target without conflicts
- Human gate for quality control

### Verification Commands

```bash
# Run specific test file
emacs --batch -l tests/test-foo.el -f ert-run-tests-batch-and-exit

# Run tests matching pattern
emacs --batch -l tests/test-foo.el --eval "(ert-run-tests-batch-and-exit \"pattern\")"

# Check file loads
emacs --batch -l file.el

# Test auto-workflow (creates optimize branch)
emacsclient -e "(gptel-auto-workflow-run-sync)"
```

### Symbol

λ tdd - test-driven development patterns