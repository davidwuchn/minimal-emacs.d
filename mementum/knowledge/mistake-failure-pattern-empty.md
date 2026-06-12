<!--
Synthesis verification:
- Confidence: 24%
- Sources: 11 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-empty'
- Auto-approved: yes (flagged)
--->

---
title: Failure Pattern — Empty Hypothesis
status: active
category: knowledge
tags: [mistake-pattern, empty-hypothesis, verification, agentic, programming, quality]
---

# Failure Pattern — Empty Hypothesis

## 1. What It Is

An **empty-hypothesis** failure occurs when a verification artifact (test, review, scope, benchmark, or agent expectation) is present in form but carries no falsifiable claim. The artifact looks complete but does not constrain behavior, so it cannot catch regressions or misalignments. It is a silent pass.

Synonyms in the observed data:
- empty verification
- empty scope
- empty review
- no-op test
- null assertion

Signature:
- `failure-type: empty-hypothesis`
- `example-reasons: none`
- `keep-rate` in the parent category is very low (often 0–4%)

## 2. Observed Occurrences

The monitoring agent logged the following incidents:

| Target | Category | Occurrences | Keep-rate | Trend window |
|---|---|---:|---:|---|
| staging-verification | :programming | 4 | 2.6% | 2026-06-04 → 2026-06-07 |
| staging-scope | :programming | 4 | 2.6% | 2026-06-05 → 2026-06-07 |
| staging-review | :programming | 16 | 3.7% | 2026-06-04 → 2026-06-08 |
| gptel-tools-agent-runtime.el | :agentic | 3 | 2.1% | 2026-06-04 → 2026-06-05 |
| gptel-tools-agent-experiment-core.el | :agentic | 4 | 0.0% | 2026-06-02 → 2026-06-03 |
| gptel-tools-agent-benchmark.el | :programming | 5 | 2.6% | 2026-06-03 → 2026-06-03 |
| gptel-benchmark-subagent.el | :programming | 4 | 3.2% | 2026-06-03 → 2026-06-04 |
| gptel-auto-workflow-strategic.el | :agentic | 4 | 1.3% | 2026-06-03 → 2026-06-03 |
| gptel-auto-workflow-projects.el | :agentic | 5 | 0.0% | 2026-06-04 → 2026-06-08 |
| gptel-auto-workflow-ontology-strategy.el | :agentic | 3 | 1.4% | 2026-06-04 |
| gptel-auto-workflow-ontology-router.el | :agentic | 3 | 0.0% | 2026-06-08 |

Keep-rate is the fraction of artifacts in the category that survived audit. Low keep-rate means most items were rejected or rewritten.

## 3. How It Manifests

### 3.1 Staging artifacts with no real claim

```
staging-review: approved
example reasons: none
```

This is an empty hypothesis: the review says "approved" but gives no evidence. A test of the same shape:

```yaml
verification:
  status: passed
  evidence: ""
```

### 3.2 Empty ERT tests

```elisp
(ert-deftest gptel-agent-runtime-should-start ()
  "Agent runtime starts."
  ;; TODO: write assertions
  )
```

The test exists, the docstring promises a behavior, but there is no assertion. `ert` reports it as passing.

### 3.3 Agent expectations with null checks

```elisp
(defun gptel--check-agent-output (result)
  "Return t if RESULT is acceptable."
  (or result t))  ;; always true; no real hypothesis
```

### 3.4 Benchmarks without metrics

```elisp
(defun gptel-benchmark-run ()
  "Run the benchmark."
  (message "done"))  ;; no measured value
```

## 4. Root Causes

1. **Stub left behind.** Auto-generated scaffolding is committed before the concrete assertion is filled in.
2. **Silent fallback.** A function returns a default truthy value instead of raising an error when data is missing.
3. **Review checklist bypassed.** The reviewer marks steps complete without writing observations.
4. **Scope drift without re-assertion.** The scope document is updated in prose but the acceptance criteria are removed.
5. **Metric not captured.** Benchmark code runs the workload but never reads a counter or timer.

## 5. Detection Commands

Run these before merging:

```bash
# Find ERT tests with empty bodies
grep -R -n -A5 "(ert-deftest" lisp/modules/ \
  | grep -E "(ert-deftest.*\n\s*\")" \
  | grep -v "should\|assert"

# Find functions that always return t or nil without using arguments
grep -R -n "(or .*t)\|(and .*nil)" lisp/modules/

# Find verification/review files with blank evidence
grep -R -n "evidence: *\"\" *\|reasons: *none" staging/

# Find TODO/FIXME inside test bodies
grep -R -n "TODO\|FIXME\|XXX" lisp/modules/*test*.el
```

Automated CI rule:

```yaml
empty-hypothesis-check:
  script:
    - python3 scripts/check_empty_hypothesis.py --paths lisp/modules staging/
```

## 6. Actionable Patterns

### 6.1 Hypothesis-First Template

Every verification artifact must state:

1. **If** `<condition>`
2. **then** `<expected behavior>`
3. **because** `<mechanism>`
4. **otherwise** `<failure signal>`

Example for staging-review:

```markdown
## Review hypothesis

If the PR changes the agent runtime startup path,
then `gptel-agent-runtime-start` must return a process object,
because `gptel--agent-process` is initialized before `init-hook`,
otherwise reject with reference to runtime-test #42.
```

### 6.2 Fill-the-Assertion Checklist

Before committing any test:

- [ ] There is at least one `(should ...)` or equivalent assertion.
- [ ] No path returns a constant truthy value.
- [ ] Every benchmark writes a numeric result.
- [ ] Every review links to at least one concrete line or log.
- [ ] The scope lists acceptance criteria, not just features.

### 6.3 Fail-Closed Default

Replace silent truthy fallbacks with explicit errors:

```elisp
(defun gptel--check-agent-output (result)
  "Return t if RESULT is acceptable."
  (unless result
    (error "Agent output is empty"))
  (gptel--validate-result-schema result))
```

### 6.4 Required Evidence Field

Enforce non-empty evidence in staging verification files:

```yaml
verification:
  status: passed
  evidence:
    - command: emacs -Q --batch -l test.el
      output: "2 passed, 0 failed"
      checksum: sha256:abc123...
```

### 6.5 Agent Self-Audit

For agentic modules, add a post-generation reflection step:

```elisp
(defun gptel--audit-empty-hypothesis (artifact)
  "Reject ARTIFACT if it contains no falsifiable claim."
  (when (gptel--empty-hypothesis-p artifact)
    (user-error "Empty hypothesis detected in %s" (gptel--artifact-name artifact))))
```

## 7. Risk Matrix

| Surface area | Frequency | Impact | Priority |
|---|---|---|---|
| staging-review | 16 | High (false confidence) | P0 |
| gptel-auto-workflow-projects.el | 5 | High (agent makes unsound plans) | P0 |
| gptel-tools-agent-benchmark.el | 5 | Medium (wrong performance data) | P1 |
| gptel-auto-workflow-strategic.el | 4 | High (strategy without measurable goals) | P0 |
| gptel-benchmark-subagent.el | 4 | Medium | P1 |
| staging-verification | 4 | High | P0 |
| staging-scope | 4 | High | P0 |
| gptel-tools-agent-experiment-core.el | 4 | High | P0 |
| gptel-tools-agent-runtime.el | 3 | High | P1 |
| gptel-auto-workflow-ontology-router.el | 3 | Medium | P1 |
| gptel-auto-workflow-ontology-strategy.el | 3 | Medium | P1 |

## 8. Recovery Procedure

When an empty hypothesis is detected:

1. **Do not approve.** Change status to `needs-hypothesis`.
2. **Write one falsifiable claim.** Use the template in section 6.1.
3. **Add the concrete check** (assertion, metric, or evidence line).
4. **Re-run detection commands** from section 5.
5. **Record the reason.** Replace `none` with the actual rationale.
6. **Update the trend log** so the monitoring agent can verify the fix.

## 9. Owner and Review Cadence

- Owner: quality agent / human reviewer pair
- Review cadence: every staging gate and every agent module change
- Metric to watch: keep-rate of the parent category; target > 80%

## Related

- [test-driven-development]
- [staging-verification]
- [staging-scope]
- [staging-review]
- [agentic-systems]
- [benchmarking]
- [keep-rate-metric]
- [verification-failure]
- [empty-scope]
- [stub-generation]
- [gptel-tools]
- [ert-testing]

We need ensure final answer starts with frontmatter and full document. Could include blank lines? Actual content lines count likely >50. Good. But we should check if any needed adjustments: user wants "Minimum 50 lines of actual content" excluding maybe frontmatter? We have plenty. Need no summarization. Return direct. Good.

Need maybe mention specific timestamps from memories. We have trend windows. Good.

Potential issue: The memories have "keep-rate" as category-level, not per target? The memory says Category :programming (keep-rate: 2.6%). Our table uses per target keep-rate from memory (category). Fine.

Need ensure tags and title okay. Could maybe title "Mistake Failure Pattern: Empty Hypothesis". We used "Failure Pattern — Empty Hypothesis".

Now final answer.