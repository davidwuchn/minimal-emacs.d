---
name: research-strategies
description: External research insights digested by LLM. Feeds into directive hypotheses.
version: 2.0
---

# External Research Insights

*Digested by LLM from internet sources. Avoid re-researching these topics.*

## Recent Discoveries (last 14 days)

# Research Findings

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-13 05:46

Researcher result for task: External research

I'll conduct targeted research following the AutoTTS-inspired strategy, prioritizing high-signal sources and top-performing topics.Good results. Let me fetch the key sources with high potential for actionable insights.Excellent! Found high-value insights. Let me search for more nil-safety specific patterns.Based on my research following the AutoTTS-inspired strategy, here are **actionable insights** for your top-performing topics:

---

## Research Digest: High-Value Findings

### 1. Structured Output Validation at Agent Boundaries (validation-guard, 18.6%)

**Source**: [Fault-Tolerant AI Agents](https://mindra.co/blog/fault-tolerant-ai-agents-failure-handling-retry-fallback-patterns)

**Key Technique**: Schema validation as first-class citizen at every agent boundary. Use JSON Schema or similar to validate outputs *before* passing to next step. When validation fails → clear signal to retry/reroute/escalate.

**Application for Emacs**:
```elisp
(defun gptel-validate-response (response schema)
  "Validate RESPONSE against SCHEMA before processing."
  (when (null response) (signal 'gptel-validation-error "Response is nil"))
  ;; Use json-parse-string with :null-object handling
  ;; Reject structurally valid but semantically wrong outputs
  )
```

**Also**: Use constrained decoding where provider supports it to reduce format failures without retry loops.

---

### 2. Sub-Agent Isolation Pattern (from karthink/gptel-agent)

**Source**: [karthink/gptel-agent](https://github.com/karthink/gptel-agent)

**Key Technique**: Sub-agents that don't share context and return concise reports. Prevents context bloat and allows task-specific tools/config.

**Application for Emacs**:
- Implement your own sub-agent specs in Markdown/Org with YAML front-matter
- Each agent gets isolated tools and context
- Main agent synthesizes from sub-agent reports

---

### 3. Tiered Retry with Prompt Adaptation (error-handling, 15.4%)

**Source**: Same fault-tolerant article

**Key Recipe**:
1. **Attempt 1**: Original prompt, standard timeout
2. **Attempt 2** (if soft failure): Prompt + error feedback, reduced temperature
3. **Attempt 3**: Simplified prompt, smaller model, tighter constraints
4. **Fallback**: Route to human review or degrade gracefully

**Anti-patterns to avoid**: Retrying with same prompt (won't fix ambiguity), unlimited retries on non-transient errors.

---

### 4. Maybe/Option Pattern for Nil Safety (nil-safety, 28.3%)

**Source**: [Null-Safety vs Maybe/Option](https://www.cnpp.dev/blog/null-safety-vs-maybe-option/index.html)

**Key Technique**: Instead of returning `nil` for "no value", wrap in `Maybe` type that forces explicit handling at call site.

**Application for Emacs**:
```elisp
;; Instead of: (defun get-cache (key) (when found value nil))
;; Use explicit Either/Maybe pattern:
(defun gptel-maybe-get (key)
  "Return (cons t value) for found, (cons nil error) for not-found."
  (if-let ((val (gethash key cache)))
      (cons t val)
    (cons nil "key-not-found")))
```

This forces callers to handle the nil case explicitly—cannot be ignored.

---

### 5. Idempotency Keys for Side Effects (validation-guard)

**Source**: Fault-tolerant article

**Key Technique**: For any write operation, generate deterministic key from (workflow-id + step-id) so retrying is safe. Prevents duplicate emails, records, etc.

**Application**: If your agent writes files or makes external calls, include idempotency checks.

---

## Metrics for Next Cycle

| Source | Insight Rate | Tokens/Insight |
|--------|--------------|----------------|
| karthink/gptel (GitHub) | High | ~500 |
| mindra.co (blog) | Very High | ~800 |
| Null-safety blogs | Medium | ~1500 |

**Recommendation**: Prioritize gptel forks and fault-tolerant AI engineering blogs for highest ROI.
---


## Internal Research Strategy Performance

*These are our own code-analysis strategies, ranked by experiment success.*

*Insufficient internal data. Run more experiments with research-enabled target selection.*

