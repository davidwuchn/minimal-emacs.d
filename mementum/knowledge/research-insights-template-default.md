---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 1.2/10
allium-issues: 0
allium-severity: 0.00
allium-status: coherent
---

# Research Strategy: template-default

*Consolidated from 59 experiments (12% keep rate).*

**Performance:** 7 kept / 0 discarded / 5 failed (EXTRACTED — from TSV)

## Successful Targets

- `lisp/modules/gptel-auto-workflow-projects.el` (6 kept / 2 failed)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 2 failed)

### Structure (deterministic scan)

```elisp-structure
defuns: gptel-auto-workflow--ensure-buffer-tables, gptel-auto-workflow--normalized-projects, gptel-auto-workflow--normalize-worktree-dir, gptel-auto-workflow--buffer-tool-snapshot, gptel-auto-workflow--routed-fsm-info, gptel-auto-workflow--get-worktree-buffer, gptel-auto-workflow--get-project-buffer, gptel-auto-workflow-add-project, gptel-auto-workflow-remove-project, gptel-auto-workflow-list-projects, gptel-auto-workflow-run-all-projects, gptel-auto-workflow--finish-queued-cron-job, gptel-auto-workflow--queue-cron-job, gptel-auto-workflow-queue-all-projects, gptel-auto-workflow--get-project-for-context, gptel-auto-workflow--advice-task-override, gptel-auto-workflow-enable-per-project-subagents, gptel-auto-workflow-disable-per-project-subagents, gptel-auto-workflow--advice-task-overlay-buffer, gptel-auto-workflow--enable-overlay-buffer-advice
defvars: gptel-auto-workflow--async, gptel-auto-workflow--process, gptel-auto-workflow--worktree-state, gptel-auto-workflow-worktree-base, gptel-auto-workflow--current-target, gptel-auto-workflow-projects, gptel-auto-workflow--project-buffers, gptel-auto-workflow--current-project, gptel-auto-workflow--run-project-root, gptel-auto-workflow--cron-job-running, gptel-auto-workflow--stats, gptel-auto-workflow--running, gptel-auto-workflow--cron-job-timer, gptel-auto-workflow--defer-subagent-env-persistence, mementum-root, gptel-auto-workflow--project-root-override), gptel-auto-workflow--research-findings-cache, gptel-auto-workflow--worktree-buffers, gptel-auto-workflow--normalized-projects-cache, gptel-auto-workflow--normalized-projects-hash
requires: cl-lib, gptel-tools-agent
provides: gptel-auto-workflow-projects
declares: gptel-auto-workflow--project-root, gptel-auto-workflow--get-worktree-dir, gptel-auto-workflow--mark-messages-start, gptel-auto-workflow--persist-status, gptel-auto-workflow-cron-safe, gptel-auto-workflow-run-async--guarded, gptel-auto-workflow-run-research, gptel-fsm-info, gptel-mementum-weekly-job, gptel-benchmark-instincts-weekly-job, gptel-auto-workflow--run-autotts-evolution, gptel-auto-workflow--reorder-fallbacks-by-ontology, gptel-auto-workflow--run-research-champion-league, gptel-auto-workflow--run-strategy-evolution
errors: error, error, error, error, error, error, error, user-error, error, error, error, error, error, signal
handlers: err, err, err, err, nil, nil, err, err, nil, nil, err, err, err, err, err, err, err
advised: gptel-agent--task, gptel-agent--task-overlay
```

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-auto-workflow-strategic.el` (1 failed)
- `lisp/modules/gptel-auto-workflow-projects.el` (6 kept / 2 failed)
- `lisp/modules/gptel-benchmark-principles.el` (1 kept / 2 failed)

## Meta-Learning Recommendations (INFERRED — from pattern analysis)

- **This strategy underperforms.** Consider evolving a new approach.
- The findings may be too generic or targeting the wrong files.
- Try combining with git history for recency bias.










## Allium Behavioral Spec (auto-generated, v3)

*3 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
# Research Strategy: Template-Default Distillation

## Scope
- **57 experiments** across 6 target files
- Focus: `gptel-auto-workflow-projects.el`, `gptel-benchmark-*.el`, `gptel-tools-*.el`

## Kept Hypotheses (Consolidated)

1. **Cache invalidation optimization** — Use `equal` instead of `eq` for project list comparison; check cache before `ensure-buffer-tables`
2. **Buffer lookup robustness** — Extract lookup into validation sequence with explicit nil guards
3. **Edge case handling** — Add `ignore-errors` around `file-attributes`; guard for empty project lists
4. **FSM state adaptation** — Add adaptive error recovery for invalid paths
5. **Symbolic comparison** — Replace `format-mode-line` with direct `mode-name` access; use `when` over `if`
6. **Runtime error prevention** — Filter `not-applicable` entries before sorting in `gptel-benchmark-eight-keys-weakest`

## Discarded
- None explicitly documented beyond the `not-applicable` crash (now kept)

## Meta-Properties Targeted
- **φ Vitality**: Progressive improvement, adaptive error recovery, edge case handling
- **Fractal Clarity**: Explicit assumptions, testable hypotheses, visible data flow
```

### Check Issues

# Review: Research Strategy Document

## Structure Assessment ✓

Well-organized with clear hierarchical sections. The breakdown is readable and scannable.

---

## Observations

### Strengths
- **Concrete scope definition** — 57 experiments, 6 files, explicit targets
- **Actionable hypotheses** — each numbered item implies a specific code change
- **Meta-properties mapped** — links technical approach to abstract quality attributes

---

### Issues to Address

| # | Issue | Location |
|---|-------|----------|
| 1 | **Hypothesis 4 is vague** — "adaptive error recovery for invalid paths" doesn't specify *what* recovery mechanism | FSM state adaptation |
| 2 | **Missing hypothesis numbering in Discarded** — unclear if `not-applicable` crash is "kept" or "discarded" | Discarded section |
| 3 | **No prioritization** — 57 experiments but no ordering (highest-impact first?) | Scope |
| 4 | **No dependency mapping** — are some experiments blocking others? | Scope |
| 5 | **Missing validation criteria** — how will you know if each hypothesis succeeds/fails? | Kept Hypotheses |

---

### Suggested Improvements

```markdown
## Success Metrics
- Each hypothesis should have: [ ] Before → [ ] After measurement

## Priority Ranking
1. Cache invalidation optimization  (likely highest impact)
2. Buffer lookup robustness         (stability)
3. ...
```

---

### Grammar Note
> "none explicitly documented beyond" → "none documented beyond"

---

Want me to expand on any hypothesis or draft concrete test cases?
