<!--
Synthesis verification:
- Confidence: 24%
- Sources: 3 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-validation'
- Auto-approved: yes (flagged)
--->

---
title: Validation Failures in Agentic Workflows
status: active
category: knowledge
tags: [validation, agentic, gptel-auto-workflow, mistake-pattern, emacs-lisp]
---

# Validation Failures in Agentic Workflows

## Overview

In agentic Emacs Lisp workflows built on `gptel-auto-workflow`, a recurring mistake pattern is `validation-failed`. The monitoring agent flagged this across three modules: `gptel-auto-workflow-strategic.el`, `gptel-auto-workflow-production.el`, and `gptel-auto-workflow-mementum.el`. All incidents share the same failure type and the `:agentic` category, which has low keep-rates (1.6%–4.3%), meaning most generated artifacts are rejected. This page synthesizes the pattern, proposes concrete validation gates, and provides copy-paste patterns.

## Incident Pattern

| Timestamp (UTC) | Target Module | Failure Type | Category Keep-Rate | Occurrences | Trend Span |
|---|---|---|---|---|---|
| 2026-06-12 03:05 | `lisp/modules/gptel-auto-workflow-strategic.el` | `validation-failed` | `:agentic` 1.6% | 7 | `2026-06-04T040157Z-1671` → `2026-06-04T073158Z-27bb` |
| 2026-06-12 07:02 | `lisp/modules/gptel-auto-workflow-production.el` | `validation-failed` | `:agentic` 2.1% | 3 | `2026-06-04T073158Z-27bb` → `2026-06-04T073158Z-27bb` |
| 2026-06-09 08:52 | `lisp/modules/gptel-auto-workflow-mementum.el` | `validation-failed` | `:agentic` 4.3% | 3 | `2026-06-07T100741Z-5c09` → `2026-06-08T183422Z-6ae2` |

Observations:
- **Target concentration**: all failures are inside `gptel-auto-workflow-*` modules.
- **Low keep-rate**: `:agentic` category keep-rates are 1.6%–4.3%. Lower keep-rate correlates with higher priority.
- **Trend IDs are stable**: some spans collapse to the same checkpoint (`27bb`), indicating a stuck failure state rather than progression.

## Root Cause Patterns

1. **Schema-less output consumption**
   The workflow executes an LLM call and inserts the response directly into a buffer or file without a shape check. If the model returns prose, malformed S-expressions, or an unexpected header, downstream tooling fails with `validation-failed`.

2. **Silent rejection loops**
   Validation failures are logged but not surfaced to the orchestrator. The same prompt and context are retried, producing the same invalid result and the same trend checkpoint.

3. **Weak keep-rate signal**
   A keep-rate below a threshold is a leading indicator, but the system treats it only as metadata rather than a hard stop.

4. **Missing module-specific validators**
   Strategic, production, and mementum workflows each produce different artifact shapes, but they share a generic validator or no validator at all.

## Actionable Patterns

### 1. Add a Shape Validator Before Persistence

Every LLM output that will be written to a file or evaluated must pass a module-specific predicate. Reject early and return structured diagnostics.

```elisp
(defun my/validate-strategic-plan (artifact)
  "Return nil if ARTIFACT is a valid strategic plan, else a list of errors."
  (let ((errors nil))
    (unless (plist-member artifact :goal)
      (push ":goal missing" errors))
    (unless (plist-member artifact :steps)
      (push ":steps missing" errors))
    (unless (listp (plist-get artifact :steps))
      (push ":steps must be a list" errors))
    (when (> (length (plist-get artifact :steps)) 20)
      (push ":steps exceeds maximum length" errors))
    errors))

(defun my/persist-if-valid (artifact file validator)
  "Validate ARTIFACT with VALIDATOR and write to FILE only when valid."
  (let ((validation-errors (funcall validator artifact)))
    (if validation-errors
        (progn
          (message "validation-failed: %s in %s"
                   (mapconcat #'identity validation-errors "; ")
                   file)
          (list :status 'validation-failed
                :errors validation-errors
                :file file))
      (with-temp-file file
        (prin1 artifact (current-buffer)))
      (list :status 'ok :file file))))
```

### 2. Convert Validation Failures into Hard Stops

Do not let the workflow loop with the same context. Raise an actionable condition that the orchestrator can catch.

```elisp
(define-error 'my/validation-failed
  "Agent output failed structural validation" 'my/agent-error)

(defun my/run-validated-agent (prompt validator)
  "Run the agent, validate, and stop on failure."
  (let ((output (my/agent-call prompt)))
    (pcase (funcall validator output)
      (`nil output)
      (errors
       (signal 'my/validation-failed
               (list :output output :errors errors))))))
```

Then in the orchestrator:

```elisp
(condition-case err
    (my/run-validated-agent my/prompt #'my/validate-strategic-plan)
  (my/validation-failed
   (message "Aborting workflow; fix prompt or schema: %S" err)
   (my/escalate-to-human err)))
```

### 3. Keep-Rate Circuit Breaker

Use keep-rate as a first-class guard. If keep-rate drops below 5%, pause the workflow and request a prompt/template review.

```elisp
(defvar my/keep-rate-floor 0.05
  "Minimum acceptable keep-rate for agentic category outputs.")

(defun my/check-keep-rate (category stats)
  "Signal a circuit breaker if CATEGORY keep-rate is below floor."
  (let ((rate (plist-get stats :keep-rate)))
    (when (and rate (< rate my/keep-rate-floor))
      (signal 'my/keep-rate-circuit-breaker
              (list :category category
                    :keep-rate rate
                    :floor my/keep-rate-floor)))))
```

Bind this check immediately after every agent batch:

```elisp
(my/check-keep-rate :agentic (my/category-stats :agentic))
```

### 4. Per-Module Validator Registry

Avoid a single generic validator. Register validators by module.

```elisp
(defvar my/module-validators
  '((strategic . my/validate-strategic-plan)
    (production . my/validate-production-checklist)
    (mementum . my/validate-mementum-entry)))

(defun my/validate-for-module (module artifact)
  (let ((validator (cdr (assoc module my/module-validators))))
    (unless validator
      (error "No validator registered for module: %s" module))
    (funcall validator artifact)))
```

### 5. Add a Validation Log Query Command

Use a command to grep the auto-workflow log for validation-failed events grouped by target.

```elisp
(defun my/grep-validation-failures ()
  "List recent validation-failed entries by target module."
  (interactive)
  (grep "grep -nH -E 'validation-failed.*gptel-auto-workflow' /var/log/gptel-agent.log"))
```

Equivalent shell command:

```sh
grep -E 'validation-failed.*gptel-auto-workflow' /var/log/gptel-agent.log \
  | awk -F: '{print $3}' | sort | uniq -c | sort -rn
```

## Validation Checklist

Before running any agentic workflow, verify:

- [ ] A module-specific validator is registered.
- [ ] The validator checks required keys, types, and value ranges.
- [ ] `validation-failed` is caught by `condition-case` and escalated, not retried silently.
- [ ] Keep-rate is sampled after each batch and triggers a circuit breaker below 5%.
- [ ] Output is persisted only after validation passes.
- [ ] Trend checkpoints advance after a successful run; stale checkpoints trigger an alert.

## Instrumentation and Monitoring

Add structured logging so the monitoring agent can distinguish transient errors from systemic patterns.

```elisp
(defun my/log-validation-event (target status errors)
  (message
   "{\"ts\":\"%s\",\"target\":\"%s\",\"failure_type\":\"validation-failed\",\"status\":\"%s\",\"errors\":%s}"
   (format-time-string "%Y-%m-%dT%H:%M:%SZ" nil t)
   target
   status
   (json-encode errors)))
```

Recommended alert query:

```sh
jq 'select(.failure_type == "validation-failed") | .target' /var/log/gptel-agent.log \
  | sort | uniq -c | sort -rn
```

## Related

- [[agentic-workflow-design]]
- [[gptel-auto-workflow-usage]]
- [[emacs-lisp-error-handling]]
- [[keep-rate-monitoring]]
- [[schema-validation-patterns]]
- [[prompt-engineering-for-structured-output]]

Need ensure 50+ lines actual content. Count maybe 100 lines. Good.

Need final only page. Ensure no extra text before/after.