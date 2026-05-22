# Research: 2026-05-22 12:10

**Strategy:** persisted-findings
**Findings hash:** 1cc6c4c5497b2bcac8d69fa51a39b2c047e160da
**Targets:** lisp/modules/gptel-benchmark-evolution.el, lisp/modules/gptel-tools-agent-strategy-harness.el
**Outcome:** 3/9 kept (33%)

**Raw Findings:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-05-22 12:02

Researcher result for task: External research turn 1/4

I'll research the priority repositories systematically, starting with own repos as directed by the evolved controller config (87% own repo priority). Let me gather findings from multiple sources.Excellent! I found rich patterns from Tier 1 repos. Let me continue with Tier 2 (agent architecture patterns):Let me continue with Tier 3 repos:Let me read key files from the fetched repos to extract concrete patterns:Let me search for external research on key patterns found:Let me check recent git history to avoid duplicating existing work:Now let me synthesize the comprehensive findings into actionable patterns:

---

## External Sources

### [deep-external] **Genesis Agent — Self-Verification Engine** (https://github.com/davidwuchn/genesis-agent)
Genesis uses 66 deterministic checks where "the LLM proposes — the machine verifies." AST parsing, exit codes, import resolution, file validation, module signatures. **Apply to us**: Implement verification functions in Emacs Lisp that check syntax validity, test exit codes, and AST structure BEFORE trusting LLM output.

### [deep-external] **Context Mode — Sandbox Tool Pattern** (https://github.com/davidwuchn/context-mode)
Context Mode achieves 98% context reduction by sandboxing tool outputs (315 KB → 5.4 KB). Stores raw data in SQLite, indexes via FTS5, retrieves only what's relevant. Session continuity preserved across context compactions. **Apply to us**: Create a sandbox module that intercepts large tool outputs (grep, read operations), stores them in SQLite/JSON, and returns compressed summaries to the LLM context.

### [deep-external] **GBrain — Self-Wiring Knowledge Graph** (https://github.com/davidwuchn/gbrain)
GBrain extracts entity references from markdown/wiki-links and creates typed graph edges (attended, works_at, invested_in) with **zero LLM calls** — pure pattern matching. Achieves +31.4 P@5 lift over vector-only RAG. **Apply to us**: Implement auto-linking in mementum memory system — parse `[[wiki/...]]` references and create bidirectional links automatically.

### [deep-external] **Nucleus — Lambda Notation Compression** (https://github.com/davidwuchn/nucleus)
Mathematical constants (φ, λ, Δ, ε) as attention magnets. Tension pairs (signal/noise, order/entropy) create productive gradients. Compact preambles that prime formal reasoning patterns. **Apply to us**: Develop nucleus-inspired preamble library for gptel prompts — map symbol combinations to semantic behaviors.

### [deep-external] **Efrit — Zero Client Intelligence, Pure Execution** (https://github.com/davidwuchn/efrit)
35+ tools provided to Claude, Claude makes all decisions. Circuit breaker prevents infinite loops. Mid-session guidance via `i` key injection. **Apply to us**: Adopt the "pure executor" principle — agent decides, elisp executes. Add checkpoint/restore for agent sessions.

### [deep-external] **Gas Town — Git-Worktree Persistence** (https://github.com/davidwuchn/gastown)
Work persists across agent restarts via git-worktree hooks. Three-tier watchdog system (Witness, Deacon, Dogs). Escalation routing (CRITICAL/HIGH/MEDIUM). **Apply to us**: Implement git-backed checkpoint system where experiment worktrees persist state and can be resumed after crashes.

### [deep-external] **nullclaw — Minimal Binary Design** (https://github.com/davidwuchn/nullclaw)
678 KB static binary, ~1 MB RAM, <2ms startup. No runtime, no GC. Feature-complete (50+ providers, 35+ tools, 10 memory engines). **Apply to us**: Target leaner elisp modules with minimal dependencies. Use `byte-compile` aggressively.

### [deep-external] **psi (Clojure) — Statechart-Driven Architecture** (https://github.com/davidwuchn/psi)
Statechart-driven agent with EQL-queryable graph. Extensions can completely customize the agent. Everything is introspectable. Minimal built-in behavior. **Apply to us**: Implement statechart-based workflow in auto-workflow — define explicit states (researching, ana
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-5wZCkt.txt. Use Read tool if you need more]...

**Digested Insights:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-05-22 12:02

Researcher result for task: External research turn 1/4

I'll research the priority repositories systematically, starting with own repos as directed by the evolved controller config (87% own repo priority). Let me gather findings from multiple sources.Excellent! I found rich patterns from Tier 1 repos. Let me continue with Tier 2 (agent architecture patterns):Let me continue with Tier 3 repos:Let me read key files from the fetched repos to extract concrete patterns:Let me search for external research on key patterns found:Let me check recent git history to avoid duplicating existing work:Now let me synthesize the comprehensive findings into actionable patterns:

---

## External Sources

### [deep-external] **Genesis Agent — Self-Verification Engine** (https://github.com/davidwuchn/genesis-agent)
Genesis uses 66 deterministic checks where "the LLM proposes — the machine verifies." AST parsing, exit codes, import resolution, file validation, module signatures. **Apply to us**: Implement verification functions in Emacs Lisp that check syntax validity, test exit codes, and AST structure BEFORE trusting LLM output.

### [deep-external] **Context Mode — Sandbox Tool Pattern** (https://github.com/davidwuchn/context-mode)
Context Mode achieves 98% context reduction by sandboxing tool outputs (315 KB → 5.4 KB). Stores raw data in SQLite, indexes via FTS5, retrieves only what's relevant. Session continuity preserved across context compactions. **Apply to us**: Create a sandbox module that intercepts large tool outputs (grep, read operations), stores them in SQLite/JSON, and returns compressed summaries to the LLM context.

### [deep-external] **GBrain — Self-Wiring Knowledge Graph** (https://github.com/davidwuchn/gbrain)
GBrain extracts entity references from markdown/wiki-links and creates typed graph edges (attended, works_at, invested_in) with **zero LLM calls** — pure pattern matching. Achieves +31.4 P@5 lift over vector-only RAG. **Apply to us**: Implement auto-linking in mementum memory system — parse `[[wiki/...]]` references and create bidirectional links automatically.

### [deep-external] **Nucleus — Lambda Notation Compression** (https://github.com/davidwuchn/nucleus)
Mathematical constants (φ, λ, Δ, ε) as attention magnets. Tension pairs (signal/noise, order/entropy) create productive gradients. Compact preambles that prime formal reasoning patterns. **Apply to us**: Develop nucleus-inspired preamble library for gptel prompts — map symbol combinations to semantic behaviors.

### [deep-external] **Efrit — Zero Client Intelligence, Pure Execution** (https://github.com/davidwuchn/efrit)
35+ tools provided to Claude, Claude makes all decisions. Circuit breaker prevents infinite loops. Mid-session guidance via `i` key injection. **Apply to us**: Adopt the "pure executor" principle — agent decides, elisp executes. Add checkpoint/restore for agent sessions.

### [deep-external] **Gas Town — Git-Worktree Persistence** (https://github.com/davidwuchn/gastown)
Work persists across agent restarts via git-worktree hooks. Three-tier watchdog system (Witness, Deacon, Dogs). Escalation routing (CRITICAL/HIGH/MEDIUM). **Apply to us**: Implement git-backed checkpoint system where experiment worktrees persist state and can be resumed after crashes.

### [deep-external] **nullclaw — Minimal Binary Design** (https://github.com/davidwuchn/nullclaw)
678 KB static binary, ~1 MB RAM, <2ms startup. No runtime, no GC. Feature-complete (50+ providers, 35+ tools, 10 memory engines). **Apply to us**: Target leaner elisp modules with minimal dependencies. Use `byte-compile` aggressively.

### [deep-external] **psi (Clojure) — Statechart-Driven Architecture** (https://github.com/davidwuchn/psi)
Statechart-driven agent with EQL-queryable graph. Extensions can completely customize the agent. Everything is introspectable. Minimal built-in behavior. **Apply to us**: Implement statechart-based workflow in auto-workflow — define explicit states (researching, ana
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-5wZCkt.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
