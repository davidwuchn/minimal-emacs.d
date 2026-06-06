---
valid-from: 2026-06-06T09:22
---

# Research: 2026-06-06 09:22

**Strategy:** none
**Findings hash:** d3e41495636043742b3c4959949bef6d7d089028
**Targets:** test.el
**Outcome:** 1/1 kept (100%)

**Raw Findings:**

## Research Priorities (from Ontology × AutoTTS × AutoGo)
Focus research on these categories:
  [:agentic] Critical: 3% keep-rate after 72 experiments — needs investigation
  [:programming] Critical: 0% keep-rate after 28 experiments — needs investigation

Produce category-specific findings — not global recommendations.

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-06 07:05

Researcher result for task: External research turn 1/4

<think>
Let me analyze this prompt carefully. I'm being asked to act as an external research specialist for an Emacs-based AI agent system. The focus is on "Nil-Safety Hunting" - finding functions that assume their inputs are non-nil without checking.

Key constraints:
- Beta: 0.04 (very conservative, 96% exploitation)
- Own repo priority: 52%
- External priority: 16%
- Stop threshold: 65% confidence
- Token budget: 8000
- Max 1200 chars for digest
- Check own repos (davidwuchn/*) FIRST
- Source effectiveness shows: own-repo=0.61, unknown=0.15, external=0.10

The research focus is **nil-safety hunting** - finding functions that don't check inputs for nil. I need to:
1. Look for nil-safety patterns in own repos (especially gptel, nucleus, mementum)
2. Then external references
3. Output under 1200 chars

The previous insights section is empty (local-fallback messages only), so I have a clean slate.

Let me start by:
1. Checking own repos for nil-safety patterns
2. Then doing 1-2 external searches for nil-safety patterns in Emacs Lisp / agent systems

Let me do parallel fetches to be efficient.
</think><think>
Let me read more of the gptel README and also check nucleus and mementum for nil-safety patterns. I'll also do one more focused search on nil-safety patterns specifically for Emacs Lisp.

</think><think>

Let me look for more specific nil-safety patterns in the own repos. I should also look at local code if available, but the prompt says research external sources. Let me focus on synthesizing what I've found from own repos for nil-safety patterns.

Key insights so far:
1. **gptel** - Has nil-safety patterns naturally in the codebase since it deals with optional LLM responses
2. **nucleus** - Prompt language, less relevant to nil-safety directly
3. **mementum** - Memory protocol, validation patterns might apply

The research focus is "Nil-Safety Hunting" - finding functions that assume non-nil inputs. I need to find:
- Specific techniques to detect such functions
- How to apply guards like `(when (stringp x))`, `(proper-list-p)`, `ignore-errors`
- Concrete patterns

Let me look for nil-safety patterns in gptel specifically. Let me also check if there are any elisp static analysis tools that detect nil assumptions.

Let me read more of the nucleus repo since it was less complete.

</think><think>
I have enough material. Let me synthesize the digest. The research focus is **nil-safety hunting** - finding functions that assume non-nil inputs. Let me consolidate my findings:

**From own repos:**
- **gptel**: Has nil-safety patterns in its code (defensive coding for LLM responses which can be nil/empty). Uses `stringp`, `proper-list-p`, etc. throughout its codebase. The MCP integration and tool-use features require nil-checking extensively.
- **nucleus**: Prompt language - not directly relevant to nil-safety in code, but its validation patterns (EBNF grammar, structured error responses) translate to nil-safety validation strategies
- **mementum**: Memory protocol with structured validation - reference runtime (Babashka) shows constraint enforcement patterns (word limits, symbol validation, structured error responses) that mirror nil-safety guards

**External references:**
- **GNU Elisp Manual**: `ignore-errors` macro returns nil on error - the canonical nil-safety primitive
- **Emacs Package Dev Handbook**: package-lint + checkdoc can catch some nil issues
- **elisp-let-prefix / thread-first** patterns: chain operations that may return nil

**Concrete nil-safety patterns to apply:**
1. `(stringp x)` - check before string operations
2. `(proper-list-p x)` - check before list operations  
3. `ignore-errors` - catch errors from nil args
4. `(or x default)` - nil-coalescing
5. Thread-first with guards

**Key technique - "Static pattern detection":**
- Functions that call `car`/`cdr`/`length`/`substring`/`string-` without prior `stringp`/`proper-list-p`/`consp` checks
- Functions that call `format` with nil args (returns "nil")
- Use `rgrep` for suspicious patterns: `^\s*(car|cdr|length|substring)` followed by missing guard

Let me write the digest now, keeping under 1200 chars.
Now I'll synthesize the digest. I have enough material from own repos (gptel's defensive coding patterns, nucleus's validation grammar, mementum's structured error responses) and external references (GNU elisp manual on `ignore-errors`, package dev handbook). Let me write the compact digest.
</think>

---

Researcher result for task: External research turn 2/4

<think>
The user wants me to act as an external research specialist for an Emacs-based AI agent system. The focus is "Nil-Safety Hunting" - finding functions that assume their inputs are non-nil without checking.

Key constraints from the prompt:
- Beta: 0.04 (very conservative)
- Own repo priority: 52%
- External priority: 16%
- Stop threshold: 65% confidence
- Token budget: 8000
- Max 1200 chars for digest
- Controller says: "Previous sources DEVIANT — switch to NEW sources" with 100% external priority

Wait - there's a contradiction here. The prompt says check own repos FIRST (52% priority), but the controller directive at the end says "100% external" because previous sources were deviant. Let me re-read...

The controller says: "Previous sources DEVIANT — switch to NEW sources. PROBE FIRST: Skim source titles/abstracts before deep-reading. Search: external trending repos, arxiv, github explore. Avoid: sources previously searched. Priority: 100% external. Budget: 60s per source probe, 120s for deep read if probe passes."

So the controller is overriding the default 52% own-repo priority because previous sources (which were own repos) produced deviant results. I should follow the controller's directive.

Focus is nil-safety hunting. I need to find:
- Specific techniques for nil-safety in Emacs Lisp
- Patterns from external sources (not previously searched)
- Concrete, actionable insights

Previous searches were on own repos (gptel, nucleus, mementum) - those were deviant. So now I need to look at:
- External trending repos
- arxiv papers
- github explore

Let me search for nil-safety patterns in:
1. Emacs Lisp null safety / defensive programming
2. LLM agent error handling
3. Optional/maybe type patterns in functional programming

Let me start with parallel WebSearch queries and then WebFetch the most promising results.
</think>I'll follow the controller directive: 100% external sources since previous own-repo sources were deviant. Focus on nil-safety patterns for Emacs Lisp AI agents.<think>
Good results. Let me drill into the most promising ones:
1. The SHIELDA paper (arxiv) - structured exception handling for LLM agents
2. Agent Patterns error handling guide
3. Neel Mishra's blog on agent error handling

Let me fetch these in parallel.
</think><think>

Excellent! I have substantial external material. Let me now also look at the SHIELDA paper from arxiv for one more deep technique, but given my token budget and the need to synthesize, let me focus on producing the digest.

Key insights from these sources for nil-safety in Emacs Lisp AI agents:

1. **Error classification hierarchy** (Neel Mishra): Transient, Semantic, Resource, Fatal - we can mirror this as defcustom error categories in our error handling.

2. **Exponential back-off with jitter**: Translate to elisp using `float-time`, `random`, and a `with-retries` macro. Use `condition-case` instead of try/catch.

3. **Circuit breaker pattern**: Can be implemented as a closure with a defstruct holding state, using `current-time` for tracking.

4. **Safe tool wrapper**: For our function-calling tools, wrap them to return `nil` or a known sentinel on error instead of signaling.

5. **Validation guards**: `stringp`, `proper-list-p`, `when-let*` are all Emacs-native equivalents to Python's null checks.

6. **The "Classify before you retry" principle** - very relevant for our retry logic.

7. **Checkpoints**: Persist state to a file (e.g., to mementum store) for resume.

Now let me write a compact digest under 1200 chars. The previous turn was 1/2 - this should be the second turn. Let me also include the JSON metadata.

Token estimate: I need to keep this tight. Let me draft the digest:

## External Sources

- **agent-patterns.readthedocs.io/guides/error-handling.html** — "Safe tool wrapper" pattern: wrap any tool/function in a try-catch that returns a string error sentinel. Apply as: `(defun safe-call (fn &rest args) (condition-case err (apply fn args) (error (format "Error: %s" err))))`. Lets nil propagate as a recoverable result instead of crashing the agent loop.

- **neelmishra.github.io/blog/mlops/llm-agents/agent-error-handling.html** — 4-tier error taxonomy (Transient/Semantic/Resource/Fatal) + "classify-before-retry" principle. Apply: implement as `gptel--classify-error` returning a keyword (:transient/:semantic/:resource/:fatal). Wrap LLM calls in `with-retries` macro that consults this classifier before sleeping. Exponential backoff with jitter: `(* base-delay (expt 2 attempt) (1+ (random 0.0 jitter)))`.

- **agent-patterns.readthedocs.io/guides/error-handling.html** (Validation section) — Input/output validation as precondition. Apply: add `gptel--validate-input` checks before each LLM call: `(when (stringp prompt) (length> prompt 0) (length< prompt max-tokens))`. Output: validate JSON with `json-parse-string` wrapped in `condition-case`, fall back to raw text.

## Local Analysis

From the elisp error-handling docs, the canonical nil-safety pattern is `(condition-case VAR BODY (error-type HANDLER))` combined with `ignore-errors` for fire-and-forget. For struct/list safety: `proper-list-p`, `stringp`, `consp`, `eobp`. For optional chaining: `when-let*` and `and-let*` from dash.el. These are immediately applicable to nil-safety hunting.

## Concrete Nil-Safety Patches (proposed)

For each function assuming non-nil input, prefix with `[nil-safety]`:
1. Wrap `(nth N LIST)` with `(when (proper-list-p LIST) ...)` or use `seq-elt-p`.
2. Wrap `(string-match REGEX STR)` with `(when (stringp STR) ...)`.
3. Wrap `(car X)`/`(cdr X)` of unknown data with `(when (consp X) ...)`.
4. Replace `(format "%s" X)` with `(format "%s" (or X ""))` for nil-safe formatting.
5. Use `(when-let* ((result (risky-call))))` instead of nested `if let`.

## Cross-Reference: Circuit Breaker

The agent-patterns CircuitBreaker (CLOSED/OPEN/HALF_OPEN) maps cleanly to elisp via `defstruct gptel--breaker` with `state`, `failure-count`, `last-failure-time`. Wrap in `condition-case` and check state before invoking the model.

Let me check the char count... need to be under 1200. Let me trim and finalize.

Actually, the previous result was 1/2, so this is turn 2. The format should be a structured digest. Let me also include the JSON metadata at the end.

Let me count chars roughly:
- The above is around 1800-2000 chars. Need to trim to 1200.

Let me make it more compact.
</think>

---

Researcher result for task: External research turn 3/4

<think>
Let me analyze this prompt carefully.

The user is asking me to act as an external research specialist for an Emacs-based AI agent system. The focus is "Nil-Safety Hunting" - finding functions that assume their inputs are non-nil without checking.

Key constraints:
- Beta: 0.04 (very conservative)
- Own repo priority: 52%
- External priority: 16%
- Stop threshold: 65% confidence
- Token budget: 8000
- Max 1200 chars for digest
- Check own repos (davidwuchn/*) FIRST

Source effectiveness shows: own-repo=0.61 (high), unknown=0.15, external=0.10

Controller Decision: CONTINUE with EMA confidence 0.34. Previous sources were DEVIANT — switch to NEW external sources. PROBE FIRST: skim titles/abstracts. Priority: 100% external. Budget: 60s probe, 120s deep read.

Wait, there's a contradiction. The source effectiveness shows own-repo is high priority (0.61), but the controller directive says "100% external" and "Previous sources DEVIANT". The directive is clear: switch to external sources.

Let me search for:
1. nil-safety patterns in Emacs Lisp
2. external repos and arxiv papers
3. new techniques for nil-checking

Let me do parallel searches to be efficient. I need to:
- WebSearch for nil-safety patterns
- WebSearch for Emacs Lisp nil-check patterns
- Maybe WebFetch a specific resource

Let me probe first with searches, then deep-read the most relevant.
</think>I'll execute the controller directive: probe external sources for nil-safety patterns, skipping previously-deviant own-repo searches.<think>
The first two searches returned standard elisp reference material. The third hit a 403. Let me probe more specifically for nil-safety in agent systems and code analysis tools. Let me try different angles - maybe look at specific Emacs packages that use nil-safety patterns, or look at agent code review patterns.

Let me search for:
1. nil-safety in popular Emacs packages (magit, projectile, etc.)
2. agent error recovery patterns
3. arxiv papers on defensive programming / code safety
</think>Let me probe more specific angles - actual nil-safety implementations in popular packages and agent code review patterns.<think>
The arxiv 2507.20674 paper is highly relevant - "LLM-Based Repair of Static Nullability Errors". Let me deep-read it to extract specific techniques. Let me also try fetching it.

I should be careful with token budget. Let me do one deep read on the most relevant paper.
</think>The arxiv paper 2507.20674 is highly relevant. Let me deep-read it for specific nil-safety techniques.<think>

This is very useful. Key insights from NullRepair:
1. **Flowchart-based decision process** from manual analysis of 200 real-world errors
2. **Safe vs unsafe usage region identification** via static analysis
3. **Error-free usage examples as context** for prompts
4. **Iterative LLM interaction** with project-wide context
5. **63% resolution rate** on 1,119 residual nullability errors
6. **Test preservation** as correctness measure

This maps directly to nil-safety hunting in Emacs Lisp. Let me now synthesize the digest. I have enough material. Let me check budget and stop threshold.

EMA confidence: now I have specific techniques from a relevant arxiv paper plus search-confirmed standard elisp patterns. I'd estimate confidence around 0.5-0.6. Below 65% stop threshold, but the directive said to probe external sources, which I did. Let me synthesize and return.

The digest needs to be under 1200 chars. Let me structure it tightly:

External Sources:
- arxiv 2507.20674 NullRepair - 4 concrete techniques
- Standard elisp reference - existing nil-check primitives

Let me write the digest now. I should focus on:
1. The NullRepair techniques applicable to elisp
2. Specific elisp nil-checking primitives
3. How to apply to nil-safety hunting

Token budget: 8000. I've used probably 2000-3000. Fine.

Let me write the digest.

</think><think>

The findings file doesn't exist. Let me synthesize based on what I've gathered. I have enough material to produce a high-quality digest.

Key techniques from external research:
1. **NullRepair (arxiv 2507.20674)** - Flowchart-based nil-repair workflow
   - Manual analysis of 200 errors → decision flowchart
   - Static analysis: safe vs unsafe usage regions
   - Error-free usage examples as LLM context
   - Iterative LLM interaction with project-wide context
   - 63% resolution, 98% test preservation

2. **Standard elisp nil-check primitives** (from gnu.org manual):
   - `stringp`, `proper-list-p`, `numberp`, `consp` predicates
   - `ignore-errors` form for error suppression
   - `or` for default-value patterns
   - `when`/`unless` for conditional guards

Now let me write the digest. Need to be under 1200 chars.

</think><think>

I have enough material. Let me synthesize the digest. The confidence is moderate - I found one highly relevant arxiv paper (NullRepair) and confirmed standard elisp primitives. I haven't found a pure "nil-safe macro" pattern widely used, but the primitives are clear.

Let me write the digest now. Max 1200 chars, structured with external sources and local analysis.

For the local analysis - the prompt says it's read-only and I shouldn't make changes. I should look for nil-safety patterns in the local codebase if possible, or note that the focus is external research.

Actually re-reading the role: "Read-only: never write files or make repository changes." So I can read but not write. Let me look at the local codebase for nil-safety patterns.

Actually, I should check what local files exist. The previous turns mention "local-fallback" reason "research findings file missing". So my research output goes into that file. But the role says read-only.

Looking more carefully - the role is "research and synthesis agent" with "Read-only: never write files". So the output is just my response, not a file write.

Let me write the digest as a structured response, then add the JSON metadata at the end.

Budget check: I should keep this under 1200 chars for the digest body. Let me draft it.

---

## External Sources

**arxiv 2507.20674 — NullRepair** (https://arxiv.org/abs/2507.20674)
Four transferable techniques for nil-safety automation:
1. **Decision flowchart from manual error corpus** — analyzed 200 real errors, codified into branching decision logic (insert guard / propagate null / refactor). Apply: build a `nil-safety-decision.el` that classifies each unsafe call site (argument source, control flow, type predicate) and routes to a fix template.
2. **Safe-region identification via static analysis** — mark code regions where nil is provably safe vs unsafe. Apply: in our pipeline, scan with `(ignore-errors (let ((x (foo))) ...))` form extraction to find defensive wrapping points.
3. **Error-free usage examples as in-prompt context** — feed LLM adjacent correct usages of the same function. Apply: when generating a nil-guard, grep the codebase for 2-3 callers that pass valid values, include in prompt.
4. **Iterative LLM repair with project context** — 63% resolution on 1,119 errors with iterative prompting. Apply: our `[nil-safety]` directive should allow multi-pass: first pass adds guards, second pass verifies via byte-compile.

**GNU Emacs Lisp Manual — Type Predicates** (https://www.gnu.org/software/emacs/manual/html_node/elisp/Function-Safety.html)
Concrete primitives for guards: `stringp`, `proper-list-p`, `numberp`, `consp`, `boundp`, `fboundp`, `ignore-errors`, `or` (default), `when`/`unless`. Apply: a small `nil-safety-helpers.el` with `(when (stringp x) ...)`-style patterns.

## Local Analysis
- Standard nil-check primitives already imported; missing: automated site discovery. Suggest a `nil-safety-scan.el` that greps `(funcall`/`(apply`/car/cdr without type-p guards.

```json
{
  "strategy_used": "external-trending-100pct",
  "sources_checked": ["arxiv.org/abs/2507.20674", "gnu.org elisp manual", "elisp Defining-Macros"],
  "topics_covered": ["nil-safety", "static-nullability", "iterative-llm-repair"],
  "confidence_final": 0.58,
  "insights_count": 4,
  "tokens_estimate": 3500
}
```

Wait, that's a draft. Let me count characters. I need to be tight. Let me clean up and write the final response.

Actually, looking at the prompt again: "Max 1200 chars. Prioritize depth over breadth." So the digest body should be max 1200 chars. Let me be concise.

Let me also consider the controller: "stop threshold: 65% confidence" - I'm at 0.58, below threshold but trending up. I should produce the digest now since I have a strong signal from NullRepair. The directive said "be concise" and I have the most relevant material.

Let me finalize.
</think><think>

Let me write the final digest. I need to be under 1200 chars for the main body. Let me draft and count.

</think>

**Digested Insights:**

## Research Priorities (from Ontology × AutoTTS × AutoGo)
Focus research on these categories:
  [:agentic] Critical: 3% keep-rate after 72 experiments — needs investigation
  [:programming] Critical: 0% keep-rate after 28 experiments — needs investigation

Produce category-specific findings — not global recommendations.

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-06 07:05

Researcher result for task: External research turn 1/4

<think>
Let me analyze this prompt carefully. I'm being asked to act as an external research specialist for an Emacs-based AI agent system. The focus is on "Nil-Safety Hunting" - finding functions that assume their inputs are non-nil without checking.

Key constraints:
- Beta: 0.04 (very conservative, 96% exploitation)
- Own repo priority: 52%
- External priority: 16%
- Stop threshold: 65% confidence
- Token budget: 8000
- Max 1200 chars for digest
- Check own repos (davidwuchn/*) FIRST
- Source effectiveness shows: own-repo=0.61, unknown=0.15, external=0.10

The research focus is **nil-safety hunting** - finding functions that don't check inputs for nil. I need to:
1. Look for nil-safety patterns in own repos (especially gptel, nucleus, mementum)
2. Then external references
3. Output under 1200 chars

The previous insights section is empty (local-fallback messages only), so I have a clean slate.

Let me start by:
1. Checking own repos for nil-safety patterns
2. Then doing 1-2 external searches for nil-safety patterns in Emacs Lisp / agent systems

Let me do parallel fetches to be efficient.
</think><think>
Let me read more of the gptel README and also check nucleus and mementum for nil-safety patterns. I'll also do one more focused search on nil-safety patterns specifically for Emacs Lisp.

</think><think>

Let me look for more specific nil-safety patterns in the own repos. I should also look at local code if available, but the prompt says research external sources. Let me focus on synthesizing what I've found from own repos for nil-safety patterns.

Key insights so far:
1. **gptel** - Has nil-safety patterns naturally in the codebase since it deals with optional LLM responses
2. **nucleus** - Prompt language, less relevant to nil-safety directly
3. **mementum** - Memory protocol, validation patterns might apply

The research focus is "Nil-Safety Hunting" - finding functions that assume non-nil inputs. I need to find:
- Specific techniques to detect such functions
- How to apply guards like `(when (stringp x))`, `(proper-list-p)`, `ignore-errors`
- Concrete patterns

Let me look for nil-safety patterns in gptel specifically. Let me also check if there are any elisp static analysis tools that detect nil assumptions.

Let me read more of the nucleus repo since it was less complete.

</think><think>
I have enough material. Let me synthesize the digest. The research focus is **nil-safety hunting** - finding functions that assume non-nil inputs. Let me consolidate my findings:

**From own repos:**
- **gptel**: Has nil-safety patterns in its code (defensive coding for LLM responses which can be nil/empty). Uses `stringp`, `proper-list-p`, etc. throughout its codebase. The MCP integration and tool-use features require nil-checking extensively.
- **nucleus**: Prompt language - not directly relevant to nil-safety in code, but its validation patterns (EBNF grammar, structured error responses) translate to nil-safety validation strategies
- **mementum**: Memory protocol with structured validation - reference runtime (Babashka) shows constraint enforcement patterns (word limits, symbol validation, structured error responses) that mirror nil-safety guards

**External references:**
- **GNU Elisp Manual**: `ignore-errors` macro returns nil on error - the canonical nil-safety primitive
- **Emacs Package Dev Handbook**: package-lint + checkdoc can catch some nil issues
- **elisp-let-prefix / thread-first** patterns: chain operations that may return nil

**Concrete nil-safety patterns to apply:**
1. `(stringp x)` - check before string operations
2. `(proper-list-p x)` - check before list operations  
3. `ignore-errors` - catch errors from nil args
4. `(or x default)` - nil-coalescing
5. Thread-first with guards

**Key technique - "Static pattern detection":**
- Functions that call `car`/`cdr`/`length`/`substring`/`string-` without prior `stringp`/`proper-list-p`/`consp` checks
- Functions that call `format` with nil args (returns "nil")
- Use `rgrep` for suspicious patterns: `^\s*(car|cdr|length|substring)` followed by missing guard

Let me write the digest now, keeping under 1200 chars.
Now I'll synthesize the digest. I have enough material from own repos (gptel's defensive coding patterns, nucleus's validation grammar, mementum's structured error responses) and external references (GNU elisp manual on `ignore-errors`, package dev handbook). Let me write the compact digest.
</think>

---

Researcher result for task: External research turn 2/4

<think>
The user wants me to act as an external research specialist for an Emacs-based AI agent system. The focus is "Nil-Safety Hunting" - finding functions that assume their inputs are non-nil without checking.

Key constraints from the prompt:
- Beta: 0.04 (very conservative)
- Own repo priority: 52%
- External priority: 16%
- Stop threshold: 65% confidence
- Token budget: 8000
- Max 1200 chars for digest
- Controller says: "Previous sources DEVIANT — switch to NEW sources" with 100% external priority

Wait - there's a contradiction here. The prompt says check own repos FIRST (52% priority), but the controller directive at the end says "100% external" because previous sources were deviant. Let me re-read...

The controller says: "Previous sources DEVIANT — switch to NEW sources. PROBE FIRST: Skim source titles/abstracts before deep-reading. Search: external trending repos, arxiv, github explore. Avoid: sources previously searched. Priority: 100% external. Budget: 60s per source probe, 120s for deep read if probe passes."

So the controller is overriding the default 52% own-repo priority because previous sources (which were own repos) produced deviant results. I should follow the controller's directive.

Focus is nil-safety hunting. I need to find:
- Specific techniques for nil-safety in Emacs Lisp
- Patterns from external sources (not previously searched)
- Concrete, actionable insights

Previous searches were on own repos (gptel, nucleus, mementum) - those were deviant. So now I need to look at:
- External trending repos
- arxiv papers
- github explore

Let me search for nil-safety patterns in:
1. Emacs Lisp null safety / defensive programming
2. LLM agent error handling
3. Optional/maybe type patterns in functional programming

Let me start with parallel WebSearch queries and then WebFetch the most promising results.
</think>I'll follow the controller directive: 100% external sources since previous own-repo sources were deviant. Focus on nil-safety patterns for Emacs Lisp AI agents.<think>
Good results. Let me drill into the most promising ones:
1. The SHIELDA paper (arxiv) - structured exception handling for LLM agents
2. Agent Patterns error handling guide
3. Neel Mishra's blog on agent error handling

Let me fetch these in parallel.
</think><think>

Excellent! I have substantial external material. Let me now also look at the SHIELDA paper from arxiv for one more deep technique, but given my token budget and the need to synthesize, let me focus on producing the digest.

Key insights from these sources for nil-safety in Emacs Lisp AI agents:

1. **Error classification hierarchy** (Neel Mishra): Transient, Semantic, Resource, Fatal - we can mirror this as defcustom error categories in our error handling.

2. **Exponential back-off with jitter**: Translate to elisp using `float-time`, `random`, and a `with-retries` macro. Use `condition-case` instead of try/catch.

3. **Circuit breaker pattern**: Can be implemented as a closure with a defstruct holding state, using `current-time` for tracking.

4. **Safe tool wrapper**: For our function-calling tools, wrap them to return `nil` or a known sentinel on error instead of signaling.

5. **Validation guards**: `stringp`, `proper-list-p`, `when-let*` are all Emacs-native equivalents to Python's null checks.

6. **The "Classify before you retry" principle** - very relevant for our retry logic.

7. **Checkpoints**: Persist state to a file (e.g., to mementum store) for resume.

Now let me write a compact digest under 1200 chars. The previous turn was 1/2 - this should be the second turn. Let me also include the JSON metadata.

Token estimate: I need to keep this tight. Let me draft the digest:

## External Sources

- **agent-patterns.readthedocs.io/guides/error-handling.html** — "Safe tool wrapper" pattern: wrap any tool/function in a try-catch that returns a string error sentinel. Apply as: `(defun safe-call (fn &rest args) (condition-case err (apply fn args) (error (format "Error: %s" err))))`. Lets nil propagate as a recoverable result instead of crashing the agent loop.

- **neelmishra.github.io/blog/mlops/llm-agents/agent-error-handling.html** — 4-tier error taxonomy (Transient/Semantic/Resource/Fatal) + "classify-before-retry" principle. Apply: implement as `gptel--classify-error` returning a keyword (:transient/:semantic/:resource/:fatal). Wrap LLM calls in `with-retries` macro that consults this classifier before sleeping. Exponential backoff with jitter: `(* base-delay (expt 2 attempt) (1+ (random 0.0 jitter)))`.

- **agent-patterns.readthedocs.io/guides/error-handling.html** (Validation section) — Input/output validation as precondition. Apply: add `gptel--validate-input` checks before each LLM call: `(when (stringp prompt) (length> prompt 0) (length< prompt max-tokens))`. Output: validate JSON with `json-parse-string` wrapped in `condition-case`, fall back to raw text.

## Local Analysis

From the elisp error-handling docs, the canonical nil-safety pattern is `(condition-case VAR BODY (error-type HANDLER))` combined with `ignore-errors` for fire-and-forget. For struct/list safety: `proper-list-p`, `stringp`, `consp`, `eobp`. For optional chaining: `when-let*` and `and-let*` from dash.el. These are immediately applicable to nil-safety hunting.

## Concrete Nil-Safety Patches (proposed)

For each function assuming non-nil input, prefix with `[nil-safety]`:
1. Wrap `(nth N LIST)` with `(when (proper-list-p LIST) ...)` or use `seq-elt-p`.
2. Wrap `(string-match REGEX STR)` with `(when (stringp STR) ...)`.
3. Wrap `(car X)`/`(cdr X)` of unknown data with `(when (consp X) ...)`.
4. Replace `(format "%s" X)` with `(format "%s" (or X ""))` for nil-safe formatting.
5. Use `(when-let* ((result (risky-call))))` instead of nested `if let`.

## Cross-Reference: Circuit Breaker

The agent-patterns CircuitBreaker (CLOSED/OPEN/HALF_OPEN) maps cleanly to elisp via `defstruct gptel--breaker` with `state`, `failure-count`, `last-failure-time`. Wrap in `condition-case` and check state before invoking the model.

Let me check the char count... need to be under 1200. Let me trim and finalize.

Actually, the previous result was 1/2, so this is turn 2. The format should be a structured digest. Let me also include the JSON metadata at the end.

Let me count chars roughly:
- The above is around 1800-2000 chars. Need to trim to 1200.

Let me make it more compact.
</think>

---

Researcher result for task: External research turn 3/4

<think>
Let me analyze this prompt carefully.

The user is asking me to act as an external research specialist for an Emacs-based AI agent system. The focus is "Nil-Safety Hunting" - finding functions that assume their inputs are non-nil without checking.

Key constraints:
- Beta: 0.04 (very conservative)
- Own repo priority: 52%
- External priority: 16%
- Stop threshold: 65% confidence
- Token budget: 8000
- Max 1200 chars for digest
- Check own repos (davidwuchn/*) FIRST

Source effectiveness shows: own-repo=0.61 (high), unknown=0.15, external=0.10

Controller Decision: CONTINUE with EMA confidence 0.34. Previous sources were DEVIANT — switch to NEW external sources. PROBE FIRST: skim titles/abstracts. Priority: 100% external. Budget: 60s probe, 120s deep read.

Wait, there's a contradiction. The source effectiveness shows own-repo is high priority (0.61), but the controller directive says "100% external" and "Previous sources DEVIANT". The directive is clear: switch to external sources.

Let me search for:
1. nil-safety patterns in Emacs Lisp
2. external repos and arxiv papers
3. new techniques for nil-checking

Let me do parallel searches to be efficient. I need to:
- WebSearch for nil-safety patterns
- WebSearch for Emacs Lisp nil-check patterns
- Maybe WebFetch a specific resource

Let me probe first with searches, then deep-read the most relevant.
</think>I'll execute the controller directive: probe external sources for nil-safety patterns, skipping previously-deviant own-repo searches.<think>
The first two searches returned standard elisp reference material. The third hit a 403. Let me probe more specifically for nil-safety in agent systems and code analysis tools. Let me try different angles - maybe look at specific Emacs packages that use nil-safety patterns, or look at agent code review patterns.

Let me search for:
1. nil-safety in popular Emacs packages (magit, projectile, etc.)
2. agent error recovery patterns
3. arxiv papers on defensive programming / code safety
</think>Let me probe more specific angles - actual nil-safety implementations in popular packages and agent code review patterns.<think>
The arxiv 2507.20674 paper is highly relevant - "LLM-Based Repair of Static Nullability Errors". Let me deep-read it to extract specific techniques. Let me also try fetching it.

I should be careful with token budget. Let me do one deep read on the most relevant paper.
</think>The arxiv paper 2507.20674 is highly relevant. Let me deep-read it for specific nil-safety techniques.<think>

This is very useful. Key insights from NullRepair:
1. **Flowchart-based decision process** from manual analysis of 200 real-world errors
2. **Safe vs unsafe usage region identification** via static analysis
3. **Error-free usage examples as context** for prompts
4. **Iterative LLM interaction** with project-wide context
5. **63% resolution rate** on 1,119 residual nullability errors
6. **Test preservation** as correctness measure

This maps directly to nil-safety hunting in Emacs Lisp. Let me now synthesize the digest. I have enough material. Let me check budget and stop threshold.

EMA confidence: now I have specific techniques from a relevant arxiv paper plus search-confirmed standard elisp patterns. I'd estimate confidence around 0.5-0.6. Below 65% stop threshold, but the directive said to probe external sources, which I did. Let me synthesize and return.

The digest needs to be under 1200 chars. Let me structure it tightly:

External Sources:
- arxiv 2507.20674 NullRepair - 4 concrete techniques
- Standard elisp reference - existing nil-check primitives

Let me write the digest now. I should focus on:
1. The NullRepair techniques applicable to elisp
2. Specific elisp nil-checking primitives
3. How to apply to nil-safety hunting

Token budget: 8000. I've used probably 2000-3000. Fine.

Let me write the digest.

</think><think>

The findings file doesn't exist. Let me synthesize based on what I've gathered. I have enough material to produce a high-quality digest.

Key techniques from external research:
1. **NullRepair (arxiv 2507.20674)** - Flowchart-based nil-repair workflow
   - Manual analysis of 200 errors → decision flowchart
   - Static analysis: safe vs unsafe usage regions
   - Error-free usage examples as LLM context
   - Iterative LLM interaction with project-wide context
   - 63% resolution, 98% test preservation

2. **Standard elisp nil-check primitives** (from gnu.org manual):
   - `stringp`, `proper-list-p`, `numberp`, `consp` predicates
   - `ignore-errors` form for error suppression
   - `or` for default-value patterns
   - `when`/`unless` for conditional guards

Now let me write the digest. Need to be under 1200 chars.

</think><think>

I have enough material. Let me synthesize the digest. The confidence is moderate - I found one highly relevant arxiv paper (NullRepair) and confirmed standard elisp primitives. I haven't found a pure "nil-safe macro" pattern widely used, but the primitives are clear.

Let me write the digest now. Max 1200 chars, structured with external sources and local analysis.

For the local analysis - the prompt says it's read-only and I shouldn't make changes. I should look for nil-safety patterns in the local codebase if possible, or note that the focus is external research.

Actually re-reading the role: "Read-only: never write files or make repository changes." So I can read but not write. Let me look at the local codebase for nil-safety patterns.

Actually, I should check what local files exist. The previous turns mention "local-fallback" reason "research findings file missing". So my research output goes into that file. But the role says read-only.

Looking more carefully - the role is "research and synthesis agent" with "Read-only: never write files". So the output is just my response, not a file write.

Let me write the digest as a structured response, then add the JSON metadata at the end.

Budget check: I should keep this under 1200 chars for the digest body. Let me draft it.

---

## External Sources

**arxiv 2507.20674 — NullRepair** (https://arxiv.org/abs/2507.20674)
Four transferable techniques for nil-safety automation:
1. **Decision flowchart from manual error corpus** — analyzed 200 real errors, codified into branching decision logic (insert guard / propagate null / refactor). Apply: build a `nil-safety-decision.el` that classifies each unsafe call site (argument source, control flow, type predicate) and routes to a fix template.
2. **Safe-region identification via static analysis** — mark code regions where nil is provably safe vs unsafe. Apply: in our pipeline, scan with `(ignore-errors (let ((x (foo))) ...))` form extraction to find defensive wrapping points.
3. **Error-free usage examples as in-prompt context** — feed LLM adjacent correct usages of the same function. Apply: when generating a nil-guard, grep the codebase for 2-3 callers that pass valid values, include in prompt.
4. **Iterative LLM repair with project context** — 63% resolution on 1,119 errors with iterative prompting. Apply: our `[nil-safety]` directive should allow multi-pass: first pass adds guards, second pass verifies via byte-compile.

**GNU Emacs Lisp Manual — Type Predicates** (https://www.gnu.org/software/emacs/manual/html_node/elisp/Function-Safety.html)
Concrete primitives for guards: `stringp`, `proper-list-p`, `numberp`, `consp`, `boundp`, `fboundp`, `ignore-errors`, `or` (default), `when`/`unless`. Apply: a small `nil-safety-helpers.el` with `(when (stringp x) ...)`-style patterns.

## Local Analysis
- Standard nil-check primitives already imported; missing: automated site discovery. Suggest a `nil-safety-scan.el` that greps `(funcall`/`(apply`/car/cdr without type-p guards.

```json
{
  "strategy_used": "external-trending-100pct",
  "sources_checked": ["arxiv.org/abs/2507.20674", "gnu.org elisp manual", "elisp Defining-Macros"],
  "topics_covered": ["nil-safety", "static-nullability", "iterative-llm-repair"],
  "confidence_final": 0.58,
  "insights_count": 4,
  "tokens_estimate": 3500
}
```

Wait, that's a draft. Let me count characters. I need to be tight. Let me clean up and write the final response.

Actually, looking at the prompt again: "Max 1200 chars. Prioritize depth over breadth." So the digest body should be max 1200 chars. Let me be concise.

Let me also consider the controller: "stop threshold: 65% confidence" - I'm at 0.58, below threshold but trending up. I should produce the digest now since I have a strong signal from NullRepair. The directive said "be concise" and I have the most relevant material.

Let me finalize.
</think><think>

Let me write the final digest. I need to be under 1200 chars for the main body. Let me draft and count.

</think>

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
