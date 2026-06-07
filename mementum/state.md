# Mementum State

> **Bootstrapped**: 2026-06-06
> **Session**: Self-evolution hooks wired into experiment core
> **Status**: All P0 priorities complete, self-heal enabled by default
> **Latest**: Unified pipeline — consolidated 4 scripts into 1
> **Active Plan**: [Monitoring Agent](knowledge/plans/monitoring-agent/plan.md) — YC Phase 2 ("Holy Shit Moment")

---

## Current Priorities (Auto-ranked)

| Priority | Item | Model | Status |
|---|---|---|---|
| **P0** | OV5 self-heal: fix workspace boundary violations | @maintainer | **COMPLETE** |
| **P0** | Refine top 20 auto-generated module docs | doc-explorer | **COMPLETE** |
| **P0** | Test pipeline wrapper in production | pipeline-ops | **COMPLETE** |
| **P0** | Optimize model routing based on task type | ov5-architect | **COMPLETE** |
| **P0** | Wire self-heal hooks into experiment core | @maintainer | **COMPLETE** |
| **P1** | Refine remaining 97 module docs with OV5 ontology/AutoTTS | doc-explorer | **IN PROGRESS** |
| **P2** | Submit PR for install.sh macOS sed | delegate-opus | **BLOCKED** (upstream) |
| **P2** | Unified pipeline: consolidate scripts | @maintainer | **COMPLETE** |
| **P1** | Monitoring Agent: Failure pattern analysis (Phase 1) | @maintainer | **COMPLETE** |

## Completed Work

### Workspace Boundary Validator (P0)

**Phase 1-4 complete** — See previous mementum entries for details.

### Module Docs Refinement (P0)

**20 critical module docs refined** — All TODOs replaced with meaningful content.

### Pipeline Wrapper Test (P0)

**Tested successfully** — Pipeline completed research -> self-evolution -> auto-workflow.

### Model Routing Optimization (P0)

**Task type detection** — Prompts are auto-analyzed and routed to optimal model.

### Self-Evolution Hooks (P0)

**New in `lisp/modules/gptel-tools-agent-base.el`:**
- `gptel-auto-workflow--self-heal-enabled` — defcustom (default: t)
- `gptel-auto-workflow-before-experiment-hook` — Hook for pre-experiment diagnostics
- `gptel-auto-workflow--run-bare-path-diagnostic` — Diagnostic helper
- `gptel-auto-workflow--auto-route-prompt` — Combined detection + routing

**Wired into `lisp/modules/gptel-tools-agent-main.el`:**
- Self-heal runs before each experiment batch
- Bare-path diagnostic runs automatically
- Results logged to console

### Unified Pipeline (P2)

**Consolidated 4 scripts into 1:**
- Deleted: `run-pipeline-ops.sh`, `refine-module-docs-with-ov5.sh`, `refine-module-docs-batch.sh`
- Merged `create_pipeline_plan`, `update_pipeline_plan`, `update_mementum_state`, `log_pipeline_patterns` into `run-pipeline.sh`
- Plan creation runs at pipeline start; state + pattern updates run at pipeline end
- `bash -n` validates syntax

## Active Patterns (from last 3 sessions)

- **Workspace boundary violation**: Self-heal accessed `/Users/davidwu/lisp/modules` — fixed by `gptel-auto-workflow--expand-workspace-path`
- **Model routing**: Keywords in prompts now auto-detect task type and route to optimal model
- **Self-evolution**: Pre-experiment diagnostics run automatically before each batch
- **Pi5 auto-evolves**: `research-insights-template-default.md`, `strategy-guidance.json` — merge=theirs
- **Unified pipeline**: 4 scripts → 1 (`run-pipeline.sh`), lifecycle hooks at start/end

## Model Routing Matrix (Static + Dynamic)

| Task Type | Detected By | Agent | Model |
|---|---|---|---|
| Code | `defun`, `fix`, `implement` | implementer | glm-5.1 |
| Review | `review`, `audit`, `validate` | delegate-opus | claude-opus-4.8 |
| Research | `research`, `analyze`, `explore` | delegate | deepseek-v4-pro |
| Creative | `brainstorm`, `design`, `create` | delegate-creative | minimax-m3 |
| Orchestration | `plan`, `coordinate`, `manage` | @maintainer | kimi-k2.6 |
| Default (no match) | — | delegate | deepseek-v4-pro |

## Self-Evolution Workflow

```
User Input → Detect Task Type → Route to Model → Self-Heal Diagnostic → Execute Experiment
```

**Self-Heal Diagnostic (runs before each experiment):**
1. Bare-path scan (directory-files, with-temp-file, find-file, insert-file-contents)
2. Boundary validation
3. Report violations

## Next Steps (Suggested by Active Mementum)

1. **Refine remaining 87 module docs** (low priority)
2. **Upstream PR** — install.sh macOS sed (blocked)

## Blockers

- **Upstream PR**: install.sh macOS sed — Pi5 fixed locally, upstream not merged

## Context for Next Session

- All P0 priorities complete
- Self-heal enabled by default (can be disabled via `gptel-auto-workflow--self-heal-enabled`)
- Boundary validator, tool checks, self-heal diagnostic committed
- 20 module docs refined
- Pipeline wrapper tested
- Model routing heuristics implemented
- Self-evolution hooks wired into experiment core
- **Unified pipeline**: 4 scripts → 1 (`run-pipeline.sh`)

---
*Active Mementum v1.0 — auto-ranked priorities, pattern detection, model routing*