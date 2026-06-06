# Mementum State

> **Bootstrapped**: 2026-06-06
> **Session**: Active Mementum Optimization
> **Status**: All 4 phases complete, 112 modules documented, OPS integrated

---

## Current Priorities (Auto-ranked)

| Priority | Item | Model | Status |
|---|---|---|---|
| **P0** | Submit PR for install.sh macOS sed | delegate-opus | **BLOCKED** (upstream) |
| **P1** | Refine top 20 auto-generated module docs | doc-explorer | Pending |
| **P2** | Test pipeline wrapper in production | pipeline-ops | Pending |
| **P3** | Optimize model routing based on task type | ov5-architect | Pending |

## Active Patterns (from last 3 sessions)

- **Pi5 auto-evolves**: `research-insights-template-default.md`, `strategy-guidance.json` — merge=theirs
- **python3 regression**: Scripts should use `jq` not python3 — use `test-script-hygiene.el`
- **Hardcoded paths**: `find` glob over machine-specific paths — use `test-script-hygiene.el`
- **defvar at top-level**: Never call functions in `defvar` — lazy init pattern

## Model Routing Matrix

| Task | Agent | Model | Why |
|---|---|---|---|
| Orchestration | @maintainer | kimi-k2.6 | Best quality/cost |
| General | delegate | deepseek-v4-pro | Default workhorse |
| Quick lookup | delegate-fast | deepseek-v4-flash | Speed |
| Strong reasoning | delegate-strong | gpt-5.4 | Hard problems |
| Hardest | delegate-gpt | gpt-5.5 | Maximum reasoning |
| Deep analysis | delegate-opus | claude-opus-4.8 | Thorough reviews |
| Second opinion | delegate-qwen | qwen3.7-max | Alternative perspective |
| Creative | delegate-creative | minimax-m3 | Brainstorming |
| Code execution | implementer | glm-5.1 | Gated changes |

## Next Steps (Suggested by Active Mementum)

1. **Refine top 20 docs** — Use `doc-explorer` to improve auto-generated module docs
2. **Test pipeline wrapper** — Run `scripts/run-pipeline-ops.sh` end-to-end
3. **Model routing heuristic** — Auto-detect task type from prompt keywords
4. **Pattern synthesis** — ≥3 similar issues → knowledge page candidate

## Blockers

- **Upstream PR**: install.sh macOS sed — Pi5 fixed locally, upstream not merged
- **Doc drift**: 107 auto-generated docs need manual refinement
- **Pipeline integration**: Not yet tested with actual experiments

## Context for Next Session

- All agents configured at `~/.config/opencode/agents/`
- Local skills at `.opencode/skills/` (run-pipeline, sync-mementum, ov5-status, ov5-handover)
- Pipeline plans at `mementum/knowledge/plans/pipeline-runs/`
- Module docs at `mementum/knowledge/modules/`
- Installer at `scripts/install-ops-global.sh`

---
*Active Mementum v1.0 — auto-ranked priorities, pattern detection, model routing*
