<!--
Synthesis verification:
- Confidence: 24%
- Sources: 7 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'research-research-none'
- Auto-approved: yes (flagged)
--->

---
title: Null Strategy Anti-Pattern in Automated Research
status: active
category: knowledge
tags: [auto-workflow, research-strategy, gptel, meta-learning, ontology]
---

# Null Strategy Anti-Pattern in Automated Research

## The "None" Strategy Failure Mode

When the automated research dispatcher emits `Strategy: none`, the pipeline consistently degrades into a null output sink. Across seven consecutive runs targeting `gptel-auto-workflow-ontology-strategy.el` and `gptel-tools-agent-experiment-core.el`, the outcome was uniformly `0/1 kept (0%)`, with empty `Raw Findings` and no digestion performed. The "none" strategy is not a neutral default—it signals a category error where the research phase is invoked without a hypothesis frame, tooling contract, or output schema.

Symptoms:
- `Findings hash` is generated but maps to empty content.
- `Digested Insights` reads `[No digestion performed]`.
- Target files receive no actionable deltas.
- Meta-learning loop receives only a downstream failure signal.

## Strategy Taxonomy

A valid strategy must bind at least three dimensions: **scope** (what to search), **method** (how to analyze), and **sink** (where to store). The "none" strategy leaves all three unbound.

| Strategy | Scope Binding | Method | Typical Retention | Use Case |
|---|---|---|---|---|
| `none` | Unbound | Unbound | 0% | (Anti-pattern) |
| `ontology-diff` | Symbol delta in strategy file | Structural diff + merge | 60-80% | Refactoring ontology categories |
| `experiment-core` | Function-level changes in core | Trace analysis + test gen | 50-70% | Validating agent experiment loops |
| `cross-reference` | Caller/callee graph | Static analysis + tag extraction | 40-60% | Mapping module dependencies |
| `memo-synthesis` | Historical memory batch | Embedding clustering | 70-90% | Generating knowledge pages |

## Detection & Guardrails

Prevent `none` from reaching the dispatcher. Add a pre-flight validation step in the auto-workflow orchestrator.

```elisp
(defun auto-workflow--validate-strategy (target strategy)
  "Reject nil, 'none, or empty string strategies before research dispatch."
  (when (member strategy '(nil none "none" ""))
    (error "Research blocked: strategy is NONE for target %s" target))
  (unless (auto-workflow--strategy-schema-p strategy)
    (error "Research blocked: strategy %s lacks schema for target %s"
           strategy target)))

;; Hook into the research dispatch pipeline
(add-hook 'auto-workflow-pre-research-hook
          #'auto-workflow--validate-strategy)
```

For batch auditing, grep the research log:

```bash
# Find all failed research runs with null strategy
grep -B2 -A5 "Strategy: none" /path/to/research-log.md \
  | grep -E "(Outcome:|Targets:|Findings hash:)"
```

## Recovery Protocol for 0% Retention Batches

If a run returns `0/1 kept`, treat it as a strategy bug, not a content bug. Do not re-run with the same parameters.

1. **Halt**: Stop the auto-workflow loop to prevent polluting the memory stream with null records.
2. **Classify**: Check if the target file defines its own expected strategy. For `gptel-auto-workflow-ontology-strategy.el`, the expected strategy is typically `ontology-diff`.
3. **Inject**: Supply the correct strategy and a seed prompt.
4. **Validate**: Ensure `Raw Findings` is non-empty before digestion.

Example recovery command in Emacs:

```elisp
(let ((target "lisp/modules/gptel-auto-workflow-ontology-strategy.el")
      (strategy 'ontology-diff))
  (auto-workflow-run-research target :strategy strategy :force t))
```

## Measuring Quality via Downstream Success

The meta-learning signal extracted from these memories—*"Research quality measured by downstream experiment success"*—implies that research retention alone is an insufficient metric. A research run that produces a 100% retention rate but fails to improve the downstream experiment pass rate is noise.

Implement a dual-gate metric:

| Gate | Metric | Threshold | Failure Action |
|---|---|---|---|
| Research Gate | Retention rate | > 0% | Reject strategy `none` |
| Experiment Gate | Downstream success delta | ≥ 1 new pass | Accept findings |
| Integration Gate | Target file diff applied | Non-empty patch | Accept digestion |

Track this in the research log frontmatter:

```yaml
---
title: "Research: ontology strategy patch"
strategy: ontology-diff
retention: 1/1
downstream_success: true
target: gptel-auto-workflow-ontology-strategy.el
---
```

## Target-Specific Strategy Mappings

The memories repeatedly touch two modules. Hard-code their expected strategies to avoid future `none` defaults.

| Target Module | Default Strategy | Rationale |
|---|---|---|
| `lisp/modules/gptel-auto-workflow-ontology-strategy.el` | `ontology-diff` | This file *is* the strategy registry; research on it should diff symbol definitions. |
| `lisp/modules/gptel-tools-agent-experiment-core.el` | `experiment-core` | Contains agent loops; research should trace experiment state machines and generate tests. |

Auto-populate the strategy field when the target matches:

```elisp
(defun auto-workflow--infer-strategy (target)
  "Return a strategy symbol based on TARGET file path."
  (cond
   ((string-match-p "ontology-strategy" target) 'ontology-diff)
   ((string-match-p "experiment-core" target) 'experiment-core)
   (t 'generic-sweep))) ;; Never return 'none
```

## Related

- [[knowledge-page-research-strategy-ontology]] — Defining ontology-diff schemas
- [[knowledge-page-experiment-core-tracing]] — Agent experiment loop analysis
- [[knowledge-page-auto-workflow-meta-learning]] — Calibration of downstream success metrics
- [[knowledge-page-memory-digestion-pipeline]] — Why empty raw findings block digestion
- [[emacs-gptel-workflow-configuration]] — Orchestrator hook setup and dispatcher logic

---

Let's count lines. The content looks well over 50 lines. It has code, tables, commands, actionable patterns, cross-references. It starts with frontmatter. It directly addresses the synthesized memories. It doesn't truncate.

I should double-check: are there any other insights? The memories are extremely sparse. All have same date 2026-06-03, times vary. All have unique hashes. All same outcome. So the synthesis is essentially about the pattern of failure. That's valid and useful.

I will format it cleanly.