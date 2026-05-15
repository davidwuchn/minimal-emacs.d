# Mementum State

> Last session: 2026-05-15 22:09

## Current Session: Controller Doom Loop + Status Bug + Architecture Integration

**Status:** Controller doom loop detection implemented (ml-intern pattern). Status bug fixed (stuck at running). Tool marker architecture integrated. CMC simulation aligned. All maphash lambdas converted. Byte-compile clean.

**Our Commits:**
- `da897ab8` — Δ controller-doom-loop: fix seq-every-p for all-equal check
- `7eb39b1e` — λ controller-doom-loop: ml-intern pattern for AutoTTS
- `4ee64400` — ⊘ Fix status stuck at running after completion

**Remote Commits Integrated:**
- Tool marker system (`f52e2f39`, `0134f584`, `61b51cbb`, `86cb3fb2`, `e5ba169c`)
- Memory tools (`971164d2`): `read_memory`, `write_memory`, `list_memories`
- Progressive shortening (Code_Inspect, Diagnostics, Grep)
- eval-rule-expr-fallback (`150d3e12`, `3e78a1bc`, `dd128fe6`)
- 38 maphash → cl-flet conversions (`bc175f88`, `3e78a1bc`)
- CMC simulation alignment (`be87a9cf`, `d7908de1`, `7d136211`, `18fb0dfe`)
- Cleanup: declare-functions, unused vars, duplicate defuns (`e0d1630d`, `d85745d0`, `4e91e461`, `dd4f136c`, `58778d4c`)

**Key Fixes:**
- **Controller doom loop**: `gptel-auto-workflow--detect-controller-doom-loop` — 3 identical signatures → corrective action (continue→branch, others→stop). Signature: `(decision, ema-range, delta-sign, output-hash)`.
- **Status stuck bug**: `finish-queued-cron-job` set phase to "idle" instead of "complete". Native-comp cache corruption handled with `condition-case`.
- **Tool markers**: 10 markers (`:can-edit`, `:can-read`, `:symbolic`, `:web`, `:memory`, `:delegates`, `:requires-project`, `:plan-excluded`, `:sandbox-excluded`, `:file-inspector`) as single source of truth.
- **CMC simulation divergence**: Missing warm-up/min-complete gates, wrong defaults (delta-slack 0.04, trend-threshold 0.04), unified fallback chains.
- **eval-rule-expr-fallback**: Lightweight rule evaluator when sandbox unavailable.
- **38 maphash → cl-flet**: Fixes daemon reader bug (lambda capture corruption).
- **Security ACL**: Added Code_Map, Code_Inspect, Diagnostics, ApplyPatch.

**Test Results:**
- doom-loop: 6/6 pass
- nucleus-tools: 26 pass + 4 skip
- byte-compile: clean (docstring warnings only)

**Architecture Patterns Captured:**
- `mementum/memories/tool-marker-architecture.md` — marker-derived classification
- `mementum/memories/cmc-simulation-divergence-pattern.md` — offline sim must mirror live
- `mementum/memories/serena-architecture-lessons.md` — context×mode×project toolset

**Next Pipeline:** 23:00 (cron: 0 23,3,7,11,15,19 * * *)

---
