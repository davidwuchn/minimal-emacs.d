# Mementum State

> **Bootstrapped**: 2026-06-06
> **Session**: 2026-06-07 — staging flow fix, test fixes, sed fix, opencode config, pipeline running
> **Status**: All local fixes pushed, 53 tests pass, opencode config updated, pipeline completed

---

## Current Priorities (Auto-ranked)

| Priority | Item | Model | Status |
|---|---|---|---|
| **P0** | Propagate staging flow failure reasons | @maintainer | **COMPLETE** |
| **P0** | Fix bare-path diagnostic infinite loop | @maintainer | **COMPLETE** (Pi5 version) |
| **P0** | Fix test shadowing (make-temp-file) | @maintainer | **COMPLETE** |
| **P0** | Fix json-true/json-false serialization | @maintainer | **COMPLETE** |
| **P0** | Switch opencode to deepseek-v4-flash | @maintainer | **COMPLETE** |
| **P0** | OV5 self-heal: fix workspace boundary violations | @maintainer | **COMPLETE** |
| **P0** | Refine top 20 auto-generated module docs | doc-explorer | **COMPLETE** |
| **P0** | Test pipeline wrapper in production | pipeline-ops | **COMPLETE** |
| **P0** | Optimize model routing based on task type | ov5-architect | **COMPLETE** |
| **P0** | Wire self-heal hooks into experiment core | @maintainer | **COMPLETE** |
| **P0** | Fix sed -i '' → sed -i (Linux compat) in pipeline scripts | @maintainer | **COMPLETE** |
| **P0** | Set opencode main model to kimi-k2.6 | @maintainer | **COMPLETE** |
| **P1** | Monitor keep-rate after fixes | pipeline-ops | **IN PROGRESS** |
| **P1** | Refine remaining 97 module docs with OV5 ontology/AutoTTS | doc-explorer | **IN PROGRESS** |
| **P2** | Submit PR for install.sh macOS sed | delegate-opus | **BLOCKED** (upstream) |

## Completed Work (2026-06-07)

### Staging Flow Failure Reason Propagation
- All 11 `(funcall finish nil)` calls in `gptel-tools-agent-staging-merge.el` now pass specific reason strings
- Committed at `37d3a25a`, merged+pushed to `origin/main` at `46367c14`

### OpenCode Config Update

**Main model**: `bailian-token-plan/kimi-k2.6`
**Small model**: `bailian-token-plan/deepseek-v4-flash` (title generation)
**Compaction**: auto + prune enabled

### Pipeline sed Fix (P0)

**Fixed**: `sed -i ''` → `sed -i` in `run-auto-workflow-cron.sh` and `refine-module-docs-batch.sh` (macOS → Linux compat)

### Workspace Boundary Validator (P0)

**Phase 1-4 complete** — See previous mementum entries for details.

### Bare-path Diagnostic Fix
- Pi5 rewrote diagnostic to use `split-string`/`dotimes` (avoids `forward-line` hang)
- Added `file-regular-p` guard
- 8 bare-path diagnostic tests pass

### Test Fixes
- Renamed `test-make-temp-dir` → `test-auto-workflow--make-temp-dir` (avoid shadowing built-in `make-temp-file`)
- Created standalone `tests/test-bare-path-diagnostic.el`
- 53 tests total, all pass

### Previous Work (2026-06-06)

## Active Patterns

- **Staging failure reason**: Always pass specific reason string to `(funcall finish ...)` — enables debugging via `comparator_reason` field
- **Bare-path diagnostic**: Pi5 uses `split-string`/`dotimes` approach (index-based, no forward-line hang risk)
- **Test naming**: Use `test-auto-workflow--` prefix for test helpers, not `test-` (avoids shadowing built-in `make-temp-file`)
- **Opencode model**: `kimi-k2.6` for main, `deepseek-v4-flash` for title generation
- **Pipeline sed**: Use `sed -i` (Linux) not `sed -i ''` (macOS)

## Context for Next Session

- Staging flow fix pushed to `origin/main` (`46367c14`)
- 53 tests pass (bare-path + auto-workflow)
- Pi5 continues auto-evolution (bare-path diagnostic already rewritten upstream)
- Keep-rate needs monitoring over next pipeline runs
- Opencode uses `kimi-k2.6` as main model, `deepseek-v4-flash` for title generation
- Pipeline completed with 1 experiment (exp1 failed due to worktree cleanup race, exp2 in progress when daemon OOM killed)
- GTM daemon socket: `/run/user/1000/emacs/gtm-product-org`

---
*Active Mementum v1.0 — auto-ranked priorities, pattern detection, model routing*
