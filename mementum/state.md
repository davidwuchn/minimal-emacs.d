# Mementum State

> Last session: 2026-03-20

## Completed (2026-03-20)

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

## Related

- mementum/knowledge/project-facts.md — Project architecture
- mementum/knowledge/nucleus-patterns.md — Eight Keys, Wu Xing, VSM (single source of truth)
- .github/workflows/evolution.yml — CI evolution cycle (skills + workflows)
- .github/workflows/skill-benchmark.yml — CI benchmark with anti-pattern detection

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
### Run: skill/test-skill @ 19:51:46
- Result: completed
