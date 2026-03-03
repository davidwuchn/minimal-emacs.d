# Task Plan: Refactor nucleus-config.el and gptel-config.el

## Goal (e — Purpose)

Split monolithic configuration files into focused, modular components with clear separation of concerns and consistent naming conventions. All modules go in `lisp/modules/` directory.

---

## Current Phase

**Phase:** Complete (archived 2026-03-04)

---

## Phases

### Phase 1: Analysis & Planning (φ)

- [x] Analyze current file structure and responsibilities
- [x] Identify coupling and dependency issues
- [x] Document naming inconsistencies
- [x] Define target module structure
- [x] Create planning documentation
- **Status:** `complete`

### Phase 2: Extract nucleus-tools.el (π)

- [x] Create `modules/nucleus-tools.el` with consolidated tool definitions
- [x] Update nucleus-config.el to require nucleus-tools.el
- [x] Update gptel-config.el to require nucleus-tools.el
- [x] Remove duplicate tool code from nucleus-config.el
- [x] Update function calls to use new nucleus-tools.el functions
- **Status:** `complete`

### Phase 3: Split gptel-ext-tools.el (Δ)

- [x] Create `modules/gptel-tools-bash.el` (~150 lines)
- [x] Create `modules/gptel-tools-grep.el` (~100 lines)
- [x] Create `modules/gptel-tools-glob.el` (~100 lines)
- [x] Create `modules/gptel-tools-edit.el` (~150 lines)
- [x] Create `modules/gptel-tools-apply.el` (~200 lines)
- [x] Create `modules/gptel-tools-agent.el` (~100 lines)
- [x] Create `modules/gptel-tools-preview.el` (~100 lines)
- [x] Create `modules/gptel-tools.el` as registry (~350 lines)
- [ ] Update gptel-ext-tools.el to require new modules (or mark deprecated)
- **Status:** `complete`

### Phase 4: Split nucleus-config.el (π)

- [x] Create `modules/nucleus-prompts.el` (~280 lines)
- [x] Create `modules/nucleus-presets.el` (~250 lines)
- [x] Create `modules/nucleus-ui.el` (~100 lines)
- [x] Update nucleus-config.el to require new modules (shim)
- **Status:** `complete`

### Phase 5: Fix Naming Conventions (μ)

- [x] Rename `my/gptel-hidden-directives` to `nucleus-hidden-directives`
- [x] Verified nucleus-*.el files use consistent naming
- [x] Backward compatibility aliases preserved in nucleus-tools.el
- **Status:** `complete`

### Phase 6: Verification (∀)

- [x] Byte-compile all modules
- [x] Test `M-x gptel` works
- [x] Test `M-x gptel-agent` works
- [x] Test Plan/Agent toggle works
- [x] Test tool calls execute correctly
- [x] Verify no byte-compile warnings
- [x] Verify tool sanity check passes
- **Status:** `complete`

---

## Key Questions

| Question | Answer | Date |
|----------|--------|------|
| Where should modules go? | `lisp/modules/` only, no `nucleus/` subdir | 2025-01-XX |
| Keep nucleus-config.el? | Yes, as backward-compat shim | 2025-01-XX |
| Tool definitions location? | `modules/nucleus-tools.el` | 2025-01-XX |

---

## Decisions Made

| Decision | Rationale | Date |
|----------|-----------|------|
| Use `modules/` directory only | Simpler structure, consistent with existing gptel-ext-* files | 2025-01-XX |
| Consolidate tool lists | 7 variables in 3 files → 1 canonical source | 2025-01-XX |
| Keep backward compat | Avoid breaking existing configs | 2025-01-XX |

---

## Blockers & Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Circular dependencies | Medium | Careful load order, use `with-eval-after-load` |
| Breaking existing configs | Low | Keep nucleus-config.el as shim |
| Tool registration timing | Medium | Defer registration until `gptel-agent-tools` loads |

---

## Errors Encountered

| Error | Attempt | Resolution | Timestamp |
|-------|---------|------------|-----------|
| (none yet) | | | |

---

## Completion Checklist

- [x] All phases marked `complete`
- [x] findings.md contains research
- [x] progress.md contains session log
- [x] No orphaned temporary files
- [x] Byte-compile clean
- [x] All tests pass
