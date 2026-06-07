# Mementum State

> **Bootstrapped**: 2026-06-06
> **Session**: 2026-06-07 — staging flow fix, test fixes, rebase
> **Status**: All local fixes pushed, 53 tests pass, opencode config updated

---

## Current Priorities (Auto-ranked)

| Priority | Item | Model | Status |
|---|---|---|---|
| **P0** | Propagate staging flow failure reasons | @maintainer | **COMPLETE** |
| **P0** | Fix bare-path diagnostic infinite loop | @maintainer | **COMPLETE** (Pi5 version) |
| **P0** | Fix test shadowing (make-temp-file) | @maintainer | **COMPLETE** |
| **P0** | Fix json-true/json-false serialization | @maintainer | **COMPLETE** |
| **P0** | Switch opencode to deepseek-v4-flash | @maintainer | **COMPLETE** |
| **P1** | Monitor keep-rate after fixes | pipeline-ops | **IN PROGRESS** |

## Completed Work (2026-06-07)

### Staging Flow Failure Reason Propagation
- All 11 `(funcall finish nil)` calls in `gptel-tools-agent-staging-merge.el` now pass specific reason strings
- Committed at `37d3a25a`, merged+pushed to `origin/main` at `46367c14`

### Bare-path Diagnostic Fix
- Pi5 rewrote diagnostic to use `split-string`/`dotimes` (avoids `forward-line` hang)
- Added `file-regular-p` guard
- 8 bare-path diagnostic tests pass

### Test Fixes
- Renamed `test-make-temp-dir` → `test-auto-workflow--make-temp-dir` (avoid shadowing built-in `make-temp-file`)
- Created standalone `tests/test-bare-path-diagnostic.el`
- 53 tests total, all pass

### Opencode Config
- Default model: `bailian-token-plan/deepseek-v4-flash` (auto compact uses default)
- Provider: Alibaba Cloud Model Studio (token-plan API)

### Previous Work (2026-06-06)

## Active Patterns

- **Staging failure reason**: Always pass specific reason string to `(funcall finish ...)` — enables debugging via `comparator_reason` field
- **Bare-path diagnostic**: Pi5 uses `split-string`/`dotimes` approach (index-based, no forward-line hang risk)
- **Test naming**: Use `test-auto-workflow--` prefix for test helpers, not `test-` (avoids shadowing built-in `make-temp-file`)
- **Opencode model**: `deepseek-v4-flash` for auto compact (cost-effective, sufficient for summarization)

## Context for Next Session

- Staging flow fix pushed to `origin/main` (`46367c14`)
- 53 tests pass (bare-path + auto-workflow)
- Pi5 continues auto-evolution (bare-path diagnostic already rewritten upstream)
- Keep-rate needs monitoring over next pipeline runs
- Opencode uses `deepseek-v4-flash` as default model
- GTM daemon socket: `/run/user/1000/emacs/gtm-product-org`

---
*Active Mementum v1.0 — auto-ranked priorities, pattern detection, model routing*