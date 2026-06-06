# OV5 Documentation

> **Source of truth:** `mementum/` — this file is a navigation layer.

## Quick Links

| What | Where |
|---|---|
| **Architecture** | `mementum/knowledge/project-facts.md` |
| **Modules** | `mementum/knowledge/modules/` |
| **Plans** | `mementum/knowledge/plans/` |
| **State** | `mementum/state.md` |

## Module Index

See `mementum/knowledge/modules/` for module documentation.

## How to Use This with OPS

1. **Before planning**: Read `mementum/state.md`
2. **Before implementing**: Check `mementum/knowledge/patterns.md`
3. **After learning**: Store in `mementum/memories/` and synthesize to `mementum/knowledge/`
4. **Session continuity**: Use `generate-handover` → updates `mementum/state.md`

## Model Routing

See `scripts/install-ops-global.sh` for the full agent/model matrix.

| Agent | Model | Role |
|---|---|---|
| @maintainer | kimi-k2.6 | Interactive orchestrator |
| delegate | deepseek-v4-pro | General subagent |
| delegate-strong | gpt-5.4 | Strong reasoning |
| delegate-gpt | gpt-5.5 | Hardest problems |
| delegate-opus | claude-opus-4.8 | Deep analysis |
| delegate-qwen | qwen3.7-max | Second opinions |
| delegate-creative | kimi-k2.6 | Creative work |
| delegate-fast | deepseek-v4-flash | Quick lookups |
| implementer | glm-5.1 | Gated code execution |
