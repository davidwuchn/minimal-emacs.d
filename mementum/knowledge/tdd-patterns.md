# TDD Patterns for Elisp

## Status: open

## Related

- tdd-first-methodology.md
- tdd-test-helper-sync.md
- surgical-edits-nested-code.md
- test-isolation-issue.md

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

### Verification Commands

```bash
# Run specific test file
emacs --batch -l tests/test-foo.el -f ert-run-tests-batch-and-exit

# Run tests matching pattern
emacs --batch -l tests/test-foo.el --eval "(ert-run-tests-batch-and-exit \"pattern\")"

# Check file loads
emacs --batch -l file.el
```

### Symbol

λ tdd - test-driven development patterns