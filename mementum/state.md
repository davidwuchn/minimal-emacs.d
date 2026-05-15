# Mementum State

> Last session: 2026-05-15

## Current Session: Pipeline Bug Fixes + Architecture Cleanup

**Status:** Major pipeline bugs fixed. CMC simulation now matches live controller. All maphash lambdas converted. Security ACL complete.

**Commits This Session:**
- `150d3e12` — eval-rule-fallback, dedup controller-config-rule-signals, skip-unless guard
- `3e78a1bc` — Fix eval-with-alist bug, 16 maphash cl-flet (pipeline modules)
- `bc175f88` — 22 remaining maphash cl-flet conversions (13 files)
- `dd4f136c` — Remove (or preset nil) no-op, dedup bash.el duplicate defuns
- `58778d4c` — Security ACL: add missing file tools, dedup cross-file defuns
- `d7908de1` — Fix trend-threshold wrong config key, remove unused vars, add defvars
- `be87a9cf` — Fix CMC simulation divergence, unify fallback chains, fix own-repo-priority default
- `7d136211` — Add 3 CMC simulation regression tests

**Key Fixes:**
- `eval-rule-expr-fallback`: lightweight rule evaluator when sandbox unavailable
- `eval` with alist-as-environment bug: controller rule validation used raw eval instead of sandbox
- `trend-threshold` pulled `:branch-threshold` (0.3) instead of `:trend-threshold` (0.04)
- CMC simulation diverged from live controller: missing warm-up/min-complete gates, wrong delta-slack (0.01 vs 0.04), wrong trend-threshold default (0.05 vs 0.04)
- `own-repo-priority` default inconsistency: 0.85 in 2 functions vs canonical 0.7
- Stop-threshold/token-budget missing dual-key fallback chains
- Security ACL missing Code_Map, Code_Inspect, Diagnostics, ApplyPatch
- 38 `maphash (lambda ...)` → `cl-flet` + `maphash #'name` across 18 files
- 4 duplicate defuns removed (bash.el ×2, load-directive-skill, discover-targets)

**Test Results:**
- research-benchmark: 19/19 (was 16/16, added 3 CMC tests)
- evolution: 3/3
- standalone-research: 3/3
- sandbox: 36/36
- nucleus-tools: 26 pass + 4 skip

**Remaining (low priority):**
- Evolution TODO:128 — pattern loading not wired into categorizer
- Security ACL still hardcoded tool names (not marker-derived)
- Guidance JSON `:own-priority` key might not match `:own-repo-priority` (needs investigation)
- Docstring width warnings (cosmetic)
- 12 sanitize tests fail in batch (gptel dependency, pre-existing)

---
