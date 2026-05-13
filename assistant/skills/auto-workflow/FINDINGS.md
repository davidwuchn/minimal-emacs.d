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
> Updated: 2026-05-13 07:01

Researcher result for task: External research

I'll invoke the researcher-prompt skill to load the specialized guidance for this research task.Now I'll execute the research task following the AutoTTS-inspired strategy. Let me start by searching for insights on the highest-success topics, prioritizing nil-safety (28.3%) and validation-guard (18.6%).

**Phase 1: High-Confidence Research (Top Topics)**Good initial results. Let me fetch the most promising sources and also search for more specific patterns.Excellent findings! Let me now search for error handling patterns and check the agent-shell project for novel techniques.Excellent! I now have comprehensive findings. Let me synthesize these into actionable insights.

---

## External Research Findings

### High-Confidence Insights (Top Priority Topics)

---

**1. Strategic Prompt Caching for LLM Agents** ⚡
- **Source**: [arXiv Paper](https://arxiv.org/html/2601.06007v2)
- **Key Finding**: Prompt caching reduces API costs 41-80% and TTFT 13-31%, BUT strategic block placement matters more than naive full-context caching.
- **Actionable**: Place **dynamic content at END** of system prompts; **exclude dynamic tool results** from cached blocks.
- **Apply to**: `gptel-ext-context-cache.el` — restructure cache keys to separate static vs dynamic segments.

---

**2. gptel Finite State Machine Architecture** 🏗️
- **Source**: [DeepWiki - karthink/gptel](https://deepwiki.com/karthink/gptel)
- **Key Finding**: Uses FSM with states `INIT → WAIT → TYPE → TOOL → DONE` for clean tool-use loops.
- **Actionable**: Our agent-loop could adopt explicit state tracking to replace implicit nil-state fallbacks.
- **Apply to**: `gptel-agent-loop.el` — replace ad-hoc nil-checks with structured state transitions.

---

**3. agent-shell Pub/Sub Event System** 🔔
- **Source**: [DeepWiki - xenodium/agent-shell](https://deepwiki.com/xenodium/agent-shell)
- **Key Finding**: Event-driven architecture with `emit-event`/`subscribe-to` for lifecycle management (init-client, tool-call-update, file-write).
- **Actionable**: Replace callback-passing with event subscriptions for loose coupling.
- **Apply to**: `gptel-tools-agent.el` — implement event bus for tool execution notifications.

---

**4. Provider Plugin Architecture** 🔌
- **Source**: [agent-shell architecture](https://deepwiki.com/xenodium/agent-shell)
- **Key Finding**: Factory functions (`make-agent-config`, `make-client`) with late binding enable provider-agnostic core.
- **Actionable**: Standardize our backend initialization via `cl-defmethod` polymorphism like gptel does.
- **Apply to**: `gptel-sandbox.el` — decouple sandbox type from execution logic.

---

**5. Error Resilience Patterns** 🛡️
- **Sources**: [dev.to](https://dev.to/thedailyagent/ai-agent-error-handling-4-resilience-patterns-in-python-12of), [agent-patterns.readthedocs](https://agent-patterns.readthedocs.io/en/stable/guides/error-handling.html)
- **Key Techniques**:
  - Retry with exponential backoff
  - Circuit breaker (fail fast after N failures)
  - Fallback chains (try alt provider → cached response → graceful failure)
- **Apply to**: `gptel-sandbox.el` — add circuit breaker state to sandbox struct.

---

**6. Lisp Nil-Safety Predicates** ✓
- **Source**: [GNU Elisp docs](https://www.gnu.org/software/emacs/manual/html_node/elisp/Function-Safety.html), [GeeksforGeeks](https://www.geeksforgeeks.org/lisp/predicates-in-lisp/)
- **Key Predicates**: `null`, `consp`, `listp`, `atom`, `symbolp`, `booleanp`, `keymapp`
- **Actionable**: Create typed-check wrappers: `(defun gptel--string-or-null (x) (or (null x) (stringp x)))`
- **Apply to**: All modules — replace `(if x ...)` with `(when-let* ((x (ensure-list x))) ...)`

---

### Rejected (Anti-patterns / Already Implemented)
- ❌ "Semantic caching" — too generic, requires vector DB
- ❌ Helper extraction — only 9% success rate
- ❌ Async refactoring — only 7% success rate
- ❌ Cleanup patterns — only 6% success rate

---

### Research Efficiency Met
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/tmp/gptel-subagent-result-pSCSyQ.txt. Use Read tool if you need more]...
---


## Internal Research Strategy Performance

*These are our own code-analysis strategies, ranked by experiment success.*

*Insufficient internal data. Run more experiments with research-enabled target selection.*

