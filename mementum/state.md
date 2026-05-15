# Mementum State

> Last session: 2026-05-15

## Current Session: Pipeline Bug Fixes + Dedup

**Status:** Fixed controller rule eval fallback, deduplicated config-rule-signals, cleaned up test guards. All batch-runnable tests green.

**Completed This Session:**
- `gptel-auto-workflow--eval-rule-expr-fallback`: lightweight evaluator for controller rule expressions when gptel-sandbox not loaded (comparisons, boolean, arithmetic, symbol lookup)
- `eval-rule-sandbox` now falls back to `eval-rule-expr-fallback` instead of returning nil
- Deduplicated `controller-config-rule-signals` from research-benchmark.el (canonical in strategic-daemon-functions.el)
- `skip-unless` guard on grep-normalize test (gptel not available in batch)
- Committed: `150d3e12`

**Previously Completed (this arc):**
- Tool marker system: 10 markers in `nucleus-tool-markers` as single source of truth
- Derived toolsets (`:readonly`, `:nucleus`, `:executor`) from markers
- Derived sandbox profiles from markers (allowed=22, readonly=12, confirming=9)
- Progressive shortening: Code_Inspect, Diagnostics, Grep (async)
- Project-level tool exclusion + readonly override via `.dir-locals.el`
- Marker-conditional prompts (memory, web sections in agent system prompt)
- Memory tools: `read_memory`, `write_memory`, `list_memories`
- Fixed: caar/cadr, cons vs list, plist-dedup, 5 busy-wait loops, DRY (controller-source-literal-string, normalize-controller-rule-expr)
- Regression tests: 7 new tests + updated toolset counts

**Test Results:**
- research-benchmark regressions: 16/16
- evolution regressions: 3/3
- standalone-research: 3/3
- sandbox: 36/36
- nucleus-tools: 26 pass + 4 skip (all batch-mode guards)
- sanitize: 37 pass + 12 fail (all pre-existing gptel-not-in-batch)

**Remaining:**
- Auto-generated JSON data files not committed (per constraint)
- 12 sanitize tests still fail in batch (gptel dependency) — not our changes
- End-to-end pipeline validation with live Emacs
- Push to origin when ready

---
