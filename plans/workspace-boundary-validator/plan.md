---
type: planning
entity: plan
plan: "workspace-boundary-validator"
status: done
created: "2026-06-06"
updated: "2026-06-06"
---

# Plan: Workspace Boundary Validator

## Objective

Implement a unified workspace boundary validator for OV5 that ensures the system only accesses `~/.emacs.d/` and explicitly assigned project directories. This prevents the self-healing and auto-workflow systems from accidentally reading/writing files outside their intended scope.

## Motivation

The self-heal byte-compiler recently attempted to access `/Users/davidwu/lisp/modules` instead of `~/.emacs.d/lisp/modules` because it used a relative path without expanding against the project root. While the immediate bug was fixed, the codebase has many other file operations that use relative paths or `default-directory` without validation. A systematic boundary validator is needed to prevent similar bugs and enforce the OV5 principle of "outside_workspace(x) → confirm(human)".

## Requirements

### Functional

- [ ] Add a single source of truth for workspace boundary validation
- [ ] Support an allow-list of workspace roots (`~/.emacs.d/` is always allowed)
- [ ] Provide a safe path expansion function that fails fast on boundary violations
- [ ] Provide a `with-workspace-boundary` macro for scoped operations
- [ ] Replace all "naked" file operations in evolution and agent modules
- [ ] Add TDD tests for the boundary validator

### Non-Functional

- [ ] No performance regression (boundary check is O(n) on allow-list size, typically small)
- [ ] Backward compatible with existing `gptel-auto-workflow--worktree-base-root` fallback
- [ ] Clear error messages when boundary is violated
- [ ] No false positives — paths within `~/.emacs.d/` must always pass

## Scope

### In Scope

- `gptel-tools-agent-base.el` — add core boundary functions
- `gptel-auto-workflow-evolution.el` — replace all relative path operations
- Other `lisp/modules/gptel-auto-workflow*.el` files — replace relative path operations
- `tests/test-auto-workflow.el` — add TDD tests

### Out of Scope

- External tool wrappers (they already have their own sandbox)
- Non-workflow modules (e.g., `gptel-ext-core.el`)
- Changing the git worktree system itself

## Definition of Done

- [ ] All file operations in workflow/evolution modules use the boundary validator
- [ ] TDD tests pass (including new boundary tests and existing regression tests)
- [ ] Manual verification: self-heal byte-compiler no longer accesses `/Users/davidwu/lisp/modules`
- [ ] Code review passed (or self-reviewed with clear reasoning)

## Testing Strategy

- Unit tests for `gptel-auto-workflow--path-within-workspace-p`
- Unit tests for `gptel-auto-workflow--expand-workspace-path`
- Unit tests for `with-workspace-boundary` macro
- Integration test: self-heal byte-compiler runs without boundary errors
- Regression test: all existing `test-gptel-tools-agent-regressions.el` pass

## Phases

| Phase | Title | Scope | Status |
|-------|-------|-------|--------|
| 1 | Core Boundary Validator | Add boundary functions to `gptel-tools-agent-base.el` + TDD tests | **DONE** — `path-within-workspace-p`, `expand-workspace-path`, `with-workspace-boundary` exist; 37 tests passing |
| 2 | Integration | Replace all relative path operations in evolution modules | **IN PROGRESS** — `gptel-auto-workflow-evolution.el` has ~50 naked file operations |

## Risks & Open Questions

| Risk/Question | Impact | Mitigation/Answer |
|---------------|--------|-------------------|
| Many files use relative paths — missing one would leave a hole | Medium | Systematic grep + replace, plus tests |
| `default-directory` might be set to something unexpected | Low | Always expand against `gptel-auto-workflow--worktree-base-root` |
| Performance: truename on every file access | Low | Allow-list is tiny; only use for file creation, not reads |
| Existing tests might depend on relative paths | Medium | Run full test suite after integration |

## Changelog

### 2026-06-06

- Plan created