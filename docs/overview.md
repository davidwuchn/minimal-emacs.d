# OV5 Documentation

> **Source of truth:** `mementum/` — this directory is a navigation layer.

## Quick Links

| What | Where |
|---|---|
| **Architecture** | `mementum/knowledge/project-facts.md` |
| **Patterns** | `mementum/knowledge/patterns.md` |
| **Self-Evolution** | `mementum/knowledge/self-evolution.md` |
| **State** | `mementum/state.md` |

## Module Index

See `mementum/knowledge/project-facts.md` for the full module inventory.

Key modules:
- `lisp/modules/gptel-auto-workflow-evolution.el` — Self-evolution engine
- `lisp/modules/gptel-auto-workflow-mementum.el` — Memory system
- `lisp/modules/gptel-auto-workflow-production.el` — Pipeline orchestration
- `lisp/modules/gptel-tools-agent-experiment-core.el` — Experiment loop

## How to Use This with OPS

1. **Before planning**: Read `mementum/state.md`
2. **Before implementing**: Check `mementum/knowledge/patterns.md`
3. **After learning**: Store in `mementum/memories/` and synthesize to `mementum/knowledge/`
4. **Session continuity**: Use `generate-handover` → updates `mementum/state.md`

## Model Routing

See `scripts/install-ops-global.sh` for the full agent/model matrix.

| Agent | Model |
|---|---|
| @maintainer | kimi-k2.6 |
| delegate | deepseek-v4-pro |
| delegate-strong | gpt-5.4 |
| delegate-gpt | gpt-5.5 |
| delegate-opus | claude-opus-4.8 |
| delegate-qwen | qwen3.7-max |
| delegate-creative | kimi-k2.6 |
| delegate-fast | deepseek-v4-flash |
| implementer | glm-5.1 |
