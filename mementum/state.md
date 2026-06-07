# Mementum State

> **Bootstrapped**: 2026-06-06
> **Session**: Pipeline reliability fixes — worktree race, OOM, ROI cold-start, boundary
> **Status**: All critical pipeline bugs fixed, daemon stable at ~417MB RSS
> **Latest**: ROI cold-start (1.0 default), empty path → workspace root, worktree preservation

---

## Current Priorities (Auto-ranked)

| Priority | Item | Model | Status |
|---|---|---|---|
| **P0** | Fix worktree race (preserve active experiments) | @maintainer | **COMPLETE** |
| **P0** | Fix OOM (4GB ulimit, 60s watchdog, 1.5GB RSS threshold) | @maintainer | **COMPLETE** |
| **P0** | Fix ROI cold-start (1.0 default for unknown/zero categories) | @maintainer | **COMPLETE** |
| **P0** | Fix boundary error (empty path → workspace root) | @maintainer | **COMPLETE** |
| **P0** | Fix sed -i '' → sed -i (Linux compat) | @maintainer | **COMPLETE** |
| **P1** | Monitoring Agent: Complete (Phases 1-3) | @maintainer | **COMPLETE** |
| **P1** | Token Economics: ROI pre-flight in experiment core | @maintainer | **COMPLETE** |
| **P1** | Production Metrics: Weighted grader scoring | @maintainer | **COMPLETE** |
| **P2** | Submit PR for install.sh macOS sed | delegate-opus | **BLOCKED** (upstream) |

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

### Monitoring Agent (P1 — YC Phase 2 "Holy Shit Moment")

**3-phase implementation complete:**
- **Phase 1**: Failure pattern analysis (classify, analyze, persist)
- **Phase 2**: Proposal generation (generate, score, validate)
- **Phase 3**: Auto-test & deploy (test, deploy, rollback, human-in-the-loop)
- Module: `lisp/modules/gptel-auto-workflow-monitoring-agent.el` (~650 lines)
- Tests: `tests/test-gptel-auto-workflow-monitoring-agent.el` (30 tests)
- Memories: `mementum/memories/monitoring-agent-*.md` (3 files)
- **Integration**: Wired into experiment core via `after-experiment-hook`

### Token Economics (P1 — YC Phase 4)

**Wired into experiment pre-flight:**
- `gptel-token-economics-roi-threshold` defcustom (default 1.0)
- `gptel-token-economics--predict-roi` (historical category ROI prediction)
- Pre-flight check rejects experiments with predicted ROI < threshold
- 4 new tests (20/20 passing)
- See: `mementum/knowledge/strategic-plans/implementation-roadmap.md` Phase 4

### Production Metrics → Grader Scoring (P1)

**Weighted scoring wired into both experiment paths:**
- `weight-score-with-production-metrics`: business-value boosts, risk penalizes
- Configurable weights: `production-weight-business-value` (0.3), `production-weight-risk-penalty` (0.5)
- Wired into main + refine experiment paths in `gptel-tools-agent-experiment-core.el`
- 4 new ERT tests (14 total): boost, fallback, configurable, symmetry

### Human Approval Queue (P2)

**High-risk monitoring agent proposals now wait for human review:**
- New module: `gptel-auto-workflow-approval-queue.el` (277 lines, 10 functions, 2 defcustoms)
- `var/approval-queue/pending/` stores proposals as .sexp files
- Interactive `review` command displays pending proposals; `approve`/`reject` archive them
- 7-day auto-expiry with prune-on-read
- Integration: `--deploy-proposal` routes `:required` risk to queue, returns `:queue-id`
- 7 ERT tests: enqueue, list, approve, reject, expiry, summary, pending-p

## Active Patterns (from last 3 sessions)

- **Workspace boundary violation**: Self-heal accessed `/Users/davidwu/lisp/modules` — fixed by `gptel-auto-workflow--expand-workspace-path`
- **Model routing**: Keywords in prompts now auto-detect task type and route to optimal model
- **Self-evolution**: Pre-experiment diagnostics run automatically before each batch
- **Pi5 auto-evolves**: `research-insights-template-default.md`, `strategy-guidance.json` — merge=theirs
- **Unified pipeline**: 4 scripts → 1 (`run-pipeline.sh`), lifecycle hooks at start/end
- **Monitoring agent**: Meta-improvement layer — detects failures, generates proposals, auto-deploys fixes
- **Monitoring agent integration**: Wired into experiment core via `after-experiment-hook`
- **Token economics**: ROI threshold rejects low-value experiments before they waste tokens
- **Production metrics**: Weighted grader scoring — business-value boosts, risk-score penalizes
- **Approval queue**: High-risk proposals → human review gate, 7-day auto-expiry

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

1. **Refine remaining 87 module docs** (P1, low urgency)
2. **Upstream PR** — install.sh macOS sed (blocked)
3. **Approval queue executor** — consume approved proposals and execute deployment (future P3)

## Blockers

- **Upstream PR**: install.sh macOS sed — Pi5 fixed locally, upstream not merged

## Context for Next Session

- All P0+P1+P2 priorities complete (approval queue closed the loop)
- Self-heal enabled by default
- Monitoring agent detects failures → generates proposals → auto-deploys (low/med risk) or queues for human (high risk)
- Token economics rejects low-ROI experiments before spending tokens
- Production metrics weight grader scores (business value boosts, risk penalizes)
- Approval queue persists high-risk proposals for human review
- Unified pipeline: 4 scripts → 1 (`run-pipeline.sh`)

---
*Active Mementum v1.0 — auto-ranked priorities, pattern detection, model routing*