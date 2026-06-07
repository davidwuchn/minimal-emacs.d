# Mementum State

> **Bootstrapped**: 2026-06-06
> **Session**: Workspace Boundary Validator — All Phases Complete
> **Status**: Core functions, tool-level checks, and self-heal diagnostic all committed and pushed

---

## Current Priorities (Auto-ranked)

| Priority | Item | Model | Status |
|---|---|---|---|
| **P0** | OV5 self-heal: fix workspace boundary violations | @maintainer | **COMPLETE** |
| **P1** | Submit PR for install.sh macOS sed | delegate-opus | **BLOCKED** (upstream) |
| **P2** | Refine top 20 auto-generated module docs | doc-explorer | Pending |
| **P3** | Test pipeline wrapper in production | pipeline-ops | Pending |
| **P4** | Optimize model routing based on task type | ov5-architect | Pending |

## Completed Work

### Workspace Boundary Validator (P0)

**Phase 1: Core Functions** (`dedb0c707`)
- `gptel-auto-workflow--allowed-workspace-roots` — defvar
- `gptel-auto-workflow--path-within-workspace-p` — predicate
- `gptel-auto-workflow--expand-workspace-path` — safe expansion
- `with-workspace-boundary` — macro
- 15 TDD tests

**Phase 2: Integration** (`dedb0c707`)
- Fixed `self-heal-byte-compiler` to use boundary-safe paths
- Prevents access to `/Users/davidwu/lisp/modules`

**Phase 3: Tool-Level Checks** (`6dee435d5`)
- Read, Write, Edit, Bash, Grep tools now validate paths
- 10 new TDD tests

**Phase 4: Self-Heal Diagnostic** (`25fb25f79`)
- New module: `gptel-auto-workflow-bare-path-diagnostic.el`
- Scans for bare relative paths in `.el` files
- Reports violations with suggested fixes

## Active Patterns (from last 3 sessions)

- **Workspace boundary violation**: Self-heal accessed `/Users/davidwu/lisp/modules` — fixed by `gptel-auto-workflow--expand-workspace-path`
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
4. **Pattern synthesis** — >=3 similar issues -> knowledge page candidate

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
- **NEW**: Boundary validator in `lisp/modules/gptel-tools-agent-base.el` (`--path-within-workspace-p`, `--expand-workspace-path`, `with-workspace-boundary`)
- **NEW**: Tool-level boundary checks in Read, Write, Edit, Bash, Grep
- **NEW**: Bare-path diagnostic in `lisp/modules/gptel-auto-workflow-bare-path-diagnostic.el`

---
*Active Mementum v1.0 — auto-ranked priorities, pattern detection, model routing*