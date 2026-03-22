# Mementum State

> Last session: 2026-03-22

## Completed (2026-03-22) — DashScope Timeout Solutions

Implemented two-pronged solution for DashScope timeout errors at high token counts:

### 1. Backend-Aware Auto-Compact Threshold

| Backend | Threshold | Reason |
|---------|-----------|--------|
| DashScope | 60% | Server-side timeout limits (~100k tokens max) |
| Others | 80% | Standard headroom for response generation |

New functions:
- `my/gptel--backend-type` — Detect current backend (:dashscope, :gemini, etc.)
- `my/gptel--effective-threshold` — Return backend-specific threshold
- `my/gptel--current-tokens` — Calculate current token count

### 2. Auto-Delegation

When context exceeds threshold:
1. Intercept `gptel-request` via advice
2. Smart context selection (full/recent/task-only)
3. Delegate to "explorer" subagent with clean context
4. Return result to original callback

New customizations:
- `my/gptel-auto-compact-threshold-dashscope` (default 0.60)
- `my/gptel-auto-delegate-enabled` (default t)
- `my/gptel-auto-delegate-threshold-absolute` (default nil)

Commands:
- `M-x my/gptel-auto-delegate-enable`
- `M-x my/gptel-auto-delegate-disable`
- `M-x my/gptel-context-window-show` — Shows backend, threshold, delegate status

File: `lisp/modules/gptel-ext-context.el` (v3.0.0, +200 lines)

---

## Completed (2026-03-22) — Defensive Nil Guards & Startup Fix

Committed fixes for `wrong-type-argument` crashes:

| Commit | Issue | Fix |
|--------|-------|-----|
| `57d96ab` | FSM markers nil → overlay crash | Guard `(markerp m) (marker-position m)` before overlay/buffer ops |
| `aa4e5e8` | HTTP status nil → `=` crash | Guard `(numberp status)` before `(= status 400)` |
| `39b69d1` | Payload estimation silent fail | Add error logging to JSON serialization fallback |
| `8a6c380` | Broken `let*` indentation | Fix `(syms ...)` binding alignment |
| `87c03ed` | Startup hang on `package-refresh-contents` | Load archives from cache (< 24h) instead of network; disable `auto-package-update-maybe` |

Files changed:
- `gptel-tools-agent.el` — Marker validation + fallback to `(point-marker)`
- `gptel-agent-loop.el` — Same marker guard pattern
- `gptel-ext-tool-confirm.el` — Tool confirm marker fallback
- `gptel-ext-retry.el` — `(numberp status)` guard, error logging
- `pre-early-init.el` — `my/package-skip-network-refresh-p` cache advice
- `lisp/init-tools.el` — Disable auto-package-update on startup

## Key Pattern

**Defensive nil guards for Elisp:**

```elisp
;; Before: crashes on nil
(= status 400)
(make-overlay start tracking-marker)

;; After: guards prevent crash
(and (numberp status) (= status 400))
(and (markerp tm) (marker-position tm) tm)
```

## Related

- mementum/knowledge/project-facts.md — Project architecture
- mementum/knowledge/nucleus-patterns.md — Eight Keys, Wu Xing, VSM

---

## Earlier (2026-03-21) — Cleanup & Review

Removed redundant code:
- Deleted 73-line gptel preview patch from `gptel-config.el` — upstream gptel.el v0.9.9.4 (commit c962243) already has the fix

Committed fixes (e93f2ae, 6f698c4):
- `gptel-config.el`: Patch gptel preview handle (now removed - upstream fixed)
- `post-init.el`: Mode-line restoration for buffers created during startup
- `init-ai.el`: Removed duplicate `ai-code--gptel-agent-setup-transform` call
- `init-org.el`: org-agenda `C-c a` → `C-c g` (C-c a used by ai-code-menu)

## Earlier (2026-03-20) — Mementum Cleanup

Noise memory prevention:
- Deleted 45 auto-generated memory files (improvement-cycle-*, evolve-skill-*) with null results
- Fixed `gptel-benchmark-auto-improve.el` — guard memory creation with insight check
- Fixed `gptel-benchmark-integrate.el` — guard feed-forward memory
- Fixed `patterns.md` stale reference to non-existent benchmark-roadmap.md

Temp file consolidation:
- Added `gptel-benchmark-make-temp-file` helper in `gptel-benchmark-core.el`
- Updated `gptel-benchmark-editor.el`, `gptel-benchmark-rollback.el` to use var/tmp/
- Updated Python scripts to output to `var/tmp/benchmark-outputs`, `var/tmp/eval-outputs`
- Removed `benchmarks/skill-results/` (temp test-run outputs)

Memory count: 10 remaining (all actual insights)

## Earlier (2026-03-20)

Closed workflow benchmark gaps:
- CI: Added workflow benchmarks to evolution.yml processing
- Anti-patterns: Added workflow-specific patterns (phase-violation, tool-misuse, context-overflow, no-verification)
- Memory: Added `gptel-workflow-retrieve-memories` for workflow context
- Trend: Added `gptel-workflow-benchmark-trend-analysis` for evolution integration

Critical hardening:
- Nil guards: Added `(or ... 0)` guards to all anti-pattern detection plist-get calls
- Defcustom: Converted `gptel-benchmark-verify-threshold` and `gptel-benchmark-verify-enabled` to proper customization

Finalized auto-evolve system:
- Fixed `gptel-benchmark--run-quick-benchmark` to use real benchmark when `gptel-agent--task` available
- Created seed benchmark data for 4 skills + 2 workflows
- CI evolution workflow can now process both skill and workflow benchmarks

## Key Insight

Two skill types:
1. **Protocol skills** (no deps) → consolidate to `mementum/knowledge/`
2. **Tool skills** (REPL/API deps) → keep skill, reference protocol via `depends:`

Auto-evolve cycle:
```
Daily Work → Collect Metrics → Detect Anti-patterns (相克) → Auto-Improve (相生) → Store Memory → Update State → Evolve
```

## Module Structure

```
gptel-benchmark-*.el (15 modules):
├── gptel-benchmark-principles.el   # Eight Keys, Wu Xing
├── gptel-benchmark-core.el         # JSON, history, utilities
├── gptel-skill-benchmark.el        # Skill test runner
├── gptel-workflow-benchmark.el     # Workflow test runner + memory + trend
├── gptel-benchmark-analysis.el     # Flaky tests, patterns
├── gptel-benchmark-comparator.el   # Version comparison
├── gptel-benchmark-evolution.el    # Ouroboros cycle + anti-patterns
├── gptel-benchmark-auto-improve.el # 相生/相克 improvements + verification
├── gptel-benchmark-memory.el       # Mementum integration + synthesis
├── gptel-benchmark-daily.el        # Daily workflow hooks
├── gptel-benchmark-integrate.el    # Evolution + Improve + LLM
├── gptel-benchmark-subagent.el     # Subagent for review
├── gptel-benchmark-tests.el        # ERT unit tests
├── gptel-benchmark-integration-tests.el # ERT integration tests
├── gptel-benchmark-llm.el          # LLM suggestions
├── gptel-benchmark-editor.el       # File editing
└── gptel-benchmark-rollback.el     # Safety rollback
```

## Test Verification

Run: `./scripts/verify-integration.sh`

```
Level 1: Unit Tests (ERT) - 38 tests
Level 2: Integration Tests (ERT) - 11 tests  
Level 3: E2E Tests (Shell) - 3 tests
```

## Benchmark Data

```
benchmarks/
├── clojure-expert-results.json
├── reddit-results.json
├── requesthunt-results.json
├── seo-geo-results.json
└── workflows/
    ├── plan_agent-results.json
    └── code_agent-results.json
```