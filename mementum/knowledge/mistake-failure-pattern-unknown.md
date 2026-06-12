<!--
Synthesis verification:
- Confidence: 24%
- Sources: 5 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-unknown'
- Auto-approved: yes (flagged)
--->

---
title: Investigating Unknown Failure Patterns in gptel Agentic/Workflow Modules
status: active
category: knowledge
tags: [gptel, agentic, failure-analysis, unknown-failures, elisp, monitoring, debugging]
---

Then sections.

The memories mention specific files:
- lisp/modules/gptel-tools-agent-runtime.el (agentic keep 2.1%, occurrences 3)
- lisp/modules/gptel-tools-agent-benchmark.el (programming keep 0%, occurrences 5)
- lisp/modules/gptel-auto-workflow-production-metrics.el (agentic 2.1%, 6)
- lisp/modules/gptel-auto-workflow-ontology-strategy.el (agentic 1.3%, 3)
- lisp/modules/gptel-auto-workflow-ontology-router.el (agentic 4.3%, 3)

We can note unknown failure type means monitoring detected failure but no classification. Need investigative protocol: preserve state, reason extraction, bisect by trend ids, reproduce using auto-workflow trends, capture errors/messages/backtraces.

Actionable patterns: classify unknown failures, add guardrails, rate-limit agentic loops, snapshot before/after, log structured reasons, unit tests for each module, deterministic replay using trend IDs.

Concrete code examples: elisp function to capture error context; command to grep trend; table; function to compute priority score; snippet to add to modules.

Cross-references: agentic-loop, keep-rate-monitoring, trend-replay, gptel-tools-error-handling, lisp/module-testing.

Need ensure 50+ lines of content. Let's make detailed. Need actual content not summaries.

Let's draft. Ensure no truncation. Final answer complete markdown.

Let's count lines later but likely >50.

Need maybe mention frontmatter lines don't count? They likely count as content? Requirement min 50 lines actual content. We'll include enough.

Let's create table with columns file, category, keep-rate, occurrences, trend window, priority score.

Priority score = occurrences / keep-rate maybe. Example: benchmark programming 0% => highest priority; handle zero division.

Add actionable protocol step-by-step.

Add code:
```elisp
(defun my/gptel-capture-unknown-failure (target category)
  "Capture context for an unclassified failure in TARGET."
  (let ((data `(:timestamp ,(current-time-string)
                :target ,target
                :category ,category
                :messages ,(buffer-substring-no-properties
                            (point-min) (point-max))
                :backtrace ,(when (fboundp 'backtrace-to-string)
                             (backtrace-to-string))
                :reason ,(or (getenv "GPTEL_LAST_REASON") "none"))))
    (with-temp-file (format "~/.cache/gptel/failures/%s-%s.json"
                            (file-name-base target)
                            (format-time-string "%Y%m%d-%H%M%S"))
      (insert (json-encode data)))))
```

Command to list trend logs:
```bash
ls ~/.cache/gptel/trends/ | grep -E "2026-06-(04|05|06|07)"
```
Or grep trends by trend id.

Reproduction harness:
```elisp
(defun my/reproduce-trend (trend-id)
  (interactive "sTrend ID: ")
  (let ((log (expand-file-name (format "%s.json" trend-id) "~/.cache/gptel/trends/")))
    (unless (file-exists-p log) (error "Trend log missing: %s" log))
    (my/gptel-replay-from-log log)))
```

Pattern checklist table.

Cross references at end.

Need make markdown content lines >50. Let's write.

Potential nuance: The memories have "Mistake" title, valid-from. We synthesize.

Let's produce final.