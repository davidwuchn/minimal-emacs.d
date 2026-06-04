# Research: 2026-06-04 09:52

**Strategy:** persisted-findings
**Findings hash:** 650f5dc66f3519652510a9191f03427629e3ac5a
**Targets:** lisp/modules/gptel-tools-agent-benchmark.el, staging-review, lisp/modules/gptel-auto-workflow-strategic.el, lisp/modules/gptel-auto-workflow-ontology-strategy.el, lisp/modules/gptel-auto-workflow-projects.el, staging-verification, lisp/modules/gptel-auto-workflow-production.el, staging-config
**Outcome:** 0/74 kept (0%)

**Raw Findings:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-06-03 21:25

Researcher result for task: External research turn 1/2

<think>The user wants me to do deep external research on the davidwuchn repositories to find patterns applicable to the Emacs AI agent system. Let me follow the research methodology:

1. Start with own repos first (highest priority per the controller)
2. Read AGENTS.md/README.md for architecture
3. Check recent commits
4. Extract 1-3 concrete patterns per repo

Let me start by fetching the key repos mentioned in the metadata:
- nucleus, mementum, gptel (explicitly mentioned)
- Also zeroclaw, context-mode, eca (from the topic performance)

I need to:
1. Fetch the GitHub pages for davidwuchn/* repos


2. Read their README/AGENTS files
3. Check recent commits
4. Extract patterns

Let me start with a web search to find the repos.
</think><think>Good, I have data from gptel and nucleus. Let me now fetch the other key repos: mementum, zeroclaw, and context-mode.
</think><think>Now let me read the specific AGENTS.md or README files for deeper patterns from the key repos. Let me check nucleus and gptel AGENTS.md files and also read the key parts of context-mode and zeroclaw.
</think><think>Now let me synthesize everything into a compact digest under 1200 chars. I have very rich material from:

Own repos:
1. **nucleus** (Emacs Lisp/EDN) - Lambda calculus notation, VSM system, Eight Keys (φμ∃∀τ), Wu Xing, OODA, modes (#=code, #=debug, etc.)
2. **gptel** (Emacs Lisp) - Tool definitions, MCP integration, multi-backend, in-place usage, introspection
3. **mementum** - Git-based memory protocol, feed-forward sessions, 3 storage types (working/memories/knowledge), 7 operations, human governance


4. **zeroclaw** (Rust) - Provider-agnostic runtime with fallback chains, workspace boundaries and security policy, tool receipts, SOP engine, ACP (JSON-RPC) for IDE integration
5. **context-mode** (TypeScript) - Context window optimization achieving 98% reduction through tool output sandboxing, session continuity via BM25 tracking, "Think in Code" paradigm, output compression
6. **eca** (Clojure) - Editor-agnostic protocol using LSP-inspired JSON-RPC, multi-model and multi-agent support, context with MCP resources

Now I'm distilling these architectural patterns into something concrete for an Emacs AI agent system under tight character constraints.
</think><think>Let me read the full context-mode README since it was stored in a temp file.
</think><think>Now I have comprehensive material from all four repos. Let me also fetch the GCP agent patterns for external reference.

Key patterns from own repos:
1. **gptel** - Tool definitions for agentic capabilities, MCP integration, multi-backend, "pause and resume" at intermediate stages
2. **nucleus** - Lambda calculus for AI cognition, attention priming via math symbols, OODA loops, 8 Keys principles
3. **mementum** - Git-based memory protocol, feed-forward sessions, 7 operations, human governance
4. **zeroclaw** - Provider-agnostic runtime, 30+ channels, fallback chains, workspace boundaries, cryptographic tool receipts


5. **context-mode** - Tool output sandboxing with 98% reduction, BM25 session continuity, "Think in Code" paradigm for context optimization

Now I'm looking at external agent patterns to round out the research.
</think><think>Let me search for GCP agent design patterns and other relevant external research.
</think><think>Now I have a comprehensive view of all four own repos plus the external references. Let me synthesize everything into a compact, actionable digest of under 1200 chars.

Key patterns from own repos:
1. **nucleus (Emacs Lisp)** - Mathematical symbol attention priming, lambda notation for AI cognition, VSM/Wu Xing framework, staged pipeline (research→assess→spec→code), Eight Keys principles
2. **gptel (Emacs Lisp)** - Tool-use protocol, MCP integration, multi-backend (curl/url-retrieve), multi-modal, introspection support, pause/resume capability
3. **mementum (multi-lang)** - Git as memory substrate, three storage types, seven operations, human governance (AI proposes, human approves, AI commits), feed-forward protocol


4. **zeroclaw (Rust)** - Provider-agnostic runtime with 30+ channel adapters, security-first architecture featuring workspace boundaries and tool receipts, SOP engine with fallback chains, and an ACP editor integration protocol
5. **context-mode (TypeScript)** - Sandboxes tool outputs to achieve 98% context reduction, uses BM25/FTS5 for session continuity across compaction events, and applies "Think in Code" principles to reduce tool calls 100x

From external sources, Google's agent design patterns include sequential pipelines, concurrent execution, and group chat orchestration for multi-agent systems. The external references show broader industry patterns—sequential, concurrent, and group-based orchestration from Google's ADK, plus academic frameworks around LLM-based multi-agent systems with specialized roles. I should now synthesize these into a compact digest that highlights what makes our approach distinct and actionable for the user's specific context.
</think>

---

Researcher result for task: External research turn 1/2

<think>The user wants me to do deep external research on the davidwuchn repositories to find patterns applicable to the Emacs AI agent system. Let me follow the research methodology:

1. Start with own repos first (highest priority per the controller)
2. Read AGENTS.md/README.md for architecture
3. Check recent commits
4. Extract 1-3 concrete patterns per repo

Let me start by fetching the key repos mentioned in the metadata:
- nucleus, mementum, gptel (explicitly mentioned)
- Also zeroclaw, context-mode, eca (from the topic performance)

I need to:
1. Fetch the GitHub pages for davidwuchn/* repos


2. Read their README/AGENTS files
3. Check recent commits
4. Extract patterns

Let me start with a web search to find the repos.
</think><think>Good, I have data from gptel and nucleus. Let me now fetch the other key repos: mementum, zeroclaw, and context-mode.
</think><think>Now let me read the specific AGENTS.md or README files for deeper patterns from the key repos. Let me check nucleus and gptel AGENTS.md files and also read the key parts of context-mode and zeroclaw.
</think><think>Now let me synthesize everything into a compact digest under 1200 chars. I have very rich material from:

Own repos:
1. **nucleus** (Emacs Lisp/EDN) - Lambda calculus notation, VSM system, Eight Keys (φμ∃∀τ), Wu Xing, OODA, modes (#=code, #=debug, etc.)
2. **gptel** (Emacs Lisp) - Tool definitions, MCP integration, multi-backend, in-place usage, introspection
3. **mementum** - Git-based memory protocol, feed-forward sessions, 3 storage types (working/memories/knowledge), 7 operations, human governance


4. **zeroclaw** (Rust) - Provider-agnostic runtime with fallback chains, workspace boundaries and security policy, tool receipts, SOP engine, ACP (JSON-RPC) for IDE integration
5. **context-mode** (TypeScript) - Context window optimization achieving 98% reduction through tool output sandboxing, session continuity via BM25 tracking, "Think in Code" paradigm, output compression
6. **eca** (Clojure) - Editor-agnostic protocol using LSP-inspired JSON-RPC, multi-model and multi-agent support, context with MCP resources

Now I'm distilling these architectural patterns into something concrete for an Emacs AI agent system under tight character constraints.
</think><think>Let me read the full context-mode README since it was stored in a temp file.
</think><think>Now I have comprehensive material from all four repos. Let me also fetch the GCP agent patterns for external reference.

Key patterns from own repos:
1. **gptel** - Tool definitions for agentic capabilities, MCP integration, multi-backend, "pause and resume" at intermediate stages
2. **nucleus** - Lambda calculus for AI cognition, attention priming via math symbols, OODA loops, 8 Keys principles
3. **mementum** - Git-based memory protocol, feed-forward sessions, 7 operations, human governance
4. **zeroclaw** - Provider-agnostic runtime, 30+ channels, fallback chains, workspace boundaries, cryptographic tool receipts


5. **context-mode** - Tool output sandboxing with 98% reduction, BM25 session continuity, "Think in Code" paradigm for context optimization

Now I'm looking at external agent patterns to round out the research.
</think><think>Let me search for GCP agent design patterns and other relevant external research.
</think><think>Now I have a comprehensive view of all four own repos plus the external references. Let me synthesize everything into a compact, actionable digest of under 1200 chars.

Key patterns from own repos:
1. **nucleus (Emacs Lisp)** - Mathematical symbol attention priming, lambda notation for AI cognition, VSM/Wu Xing framework, staged pipeline (research→assess→spec→code), Eight Keys principles
2. **gptel (Emacs Lisp)** - Tool-use protocol, MCP integration, multi-backend (curl/url-retrieve), multi-modal, introspection support, pause/resume capability
3. **mementum (multi-lang)** - Git as memory substrate, three storage types, seven operations, human governance (AI proposes, human approves, AI commits), feed-forward protocol


4. **zeroclaw (Rust)** - Provider-agnostic runtime with 30+ channel adapters, security-first architecture featuring workspace boundaries and tool receipts, SOP engine with fallback chains, and an ACP editor integration protocol
5. **context-mode (TypeScript)** - Sandboxes tool outputs to achieve 98% context reduction, uses BM25/FTS5 for session continuity across compaction events, and applies "Think in Code" principles to reduce tool calls 100x

From external sources, Google's agent design patterns include sequential pipelines, concurrent execution, and group chat orchestration for multi-agent systems. The external references show broader industry patterns—sequential, concurrent, and group-based orchestration from Google's ADK, plus academic frameworks around LLM-based multi-agent systems with specialized roles. I should now synthesize these into a compact digest that highlights what makes our approach distinct and actionable for the user's specific context.
</think>

**Digested Insights:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-06-03 21:25

Researcher result for task: External research turn 1/2

<think>The user wants me to do deep external research on the davidwuchn repositories to find patterns applicable to the Emacs AI agent system. Let me follow the research methodology:

1. Start with own repos first (highest priority per the controller)
2. Read AGENTS.md/README.md for architecture
3. Check recent commits
4. Extract 1-3 concrete patterns per repo

Let me start by fetching the key repos mentioned in the metadata:
- nucleus, mementum, gptel (explicitly mentioned)
- Also zeroclaw, context-mode, eca (from the topic performance)

I need to:
1. Fetch the GitHub pages for davidwuchn/* repos


2. Read their README/AGENTS files
3. Check recent commits
4. Extract patterns

Let me start with a web search to find the repos.
</think><think>Good, I have data from gptel and nucleus. Let me now fetch the other key repos: mementum, zeroclaw, and context-mode.
</think><think>Now let me read the specific AGENTS.md or README files for deeper patterns from the key repos. Let me check nucleus and gptel AGENTS.md files and also read the key parts of context-mode and zeroclaw.
</think><think>Now let me synthesize everything into a compact digest under 1200 chars. I have very rich material from:

Own repos:
1. **nucleus** (Emacs Lisp/EDN) - Lambda calculus notation, VSM system, Eight Keys (φμ∃∀τ), Wu Xing, OODA, modes (#=code, #=debug, etc.)
2. **gptel** (Emacs Lisp) - Tool definitions, MCP integration, multi-backend, in-place usage, introspection
3. **mementum** - Git-based memory protocol, feed-forward sessions, 3 storage types (working/memories/knowledge), 7 operations, human governance


4. **zeroclaw** (Rust) - Provider-agnostic runtime with fallback chains, workspace boundaries and security policy, tool receipts, SOP engine, ACP (JSON-RPC) for IDE integration
5. **context-mode** (TypeScript) - Context window optimization achieving 98% reduction through tool output sandboxing, session continuity via BM25 tracking, "Think in Code" paradigm, output compression
6. **eca** (Clojure) - Editor-agnostic protocol using LSP-inspired JSON-RPC, multi-model and multi-agent support, context with MCP resources

Now I'm distilling these architectural patterns into something concrete for an Emacs AI agent system under tight character constraints.
</think><think>Let me read the full context-mode README since it was stored in a temp file.
</think><think>Now I have comprehensive material from all four repos. Let me also fetch the GCP agent patterns for external reference.

Key patterns from own repos:
1. **gptel** - Tool definitions for agentic capabilities, MCP integration, multi-backend, "pause and resume" at intermediate stages
2. **nucleus** - Lambda calculus for AI cognition, attention priming via math symbols, OODA loops, 8 Keys principles
3. **mementum** - Git-based memory protocol, feed-forward sessions, 7 operations, human governance
4. **zeroclaw** - Provider-agnostic runtime, 30+ channels, fallback chains, workspace boundaries, cryptographic tool receipts


5. **context-mode** - Tool output sandboxing with 98% reduction, BM25 session continuity, "Think in Code" paradigm for context optimization

Now I'm looking at external agent patterns to round out the research.
</think><think>Let me search for GCP agent design patterns and other relevant external research.
</think><think>Now I have a comprehensive view of all four own repos plus the external references. Let me synthesize everything into a compact, actionable digest of under 1200 chars.

Key patterns from own repos:
1. **nucleus (Emacs Lisp)** - Mathematical symbol attention priming, lambda notation for AI cognition, VSM/Wu Xing framework, staged pipeline (research→assess→spec→code), Eight Keys principles
2. **gptel (Emacs Lisp)** - Tool-use protocol, MCP integration, multi-backend (curl/url-retrieve), multi-modal, introspection support, pause/resume capability
3. **mementum (multi-lang)** - Git as memory substrate, three storage types, seven operations, human governance (AI proposes, human approves, AI commits), feed-forward protocol


4. **zeroclaw (Rust)** - Provider-agnostic runtime with 30+ channel adapters, security-first architecture featuring workspace boundaries and tool receipts, SOP engine with fallback chains, and an ACP editor integration protocol
5. **context-mode (TypeScript)** - Sandboxes tool outputs to achieve 98% context reduction, uses BM25/FTS5 for session continuity across compaction events, and applies "Think in Code" principles to reduce tool calls 100x

From external sources, Google's agent design patterns include sequential pipelines, concurrent execution, and group chat orchestration for multi-agent systems. The external references show broader industry patterns—sequential, concurrent, and group-based orchestration from Google's ADK, plus academic frameworks around LLM-based multi-agent systems with specialized roles. I should now synthesize these into a compact digest that highlights what makes our approach distinct and actionable for the user's specific context.
</think>

---

Researcher result for task: External research turn 1/2

<think>The user wants me to do deep external research on the davidwuchn repositories to find patterns applicable to the Emacs AI agent system. Let me follow the research methodology:

1. Start with own repos first (highest priority per the controller)
2. Read AGENTS.md/README.md for architecture
3. Check recent commits
4. Extract 1-3 concrete patterns per repo

Let me start by fetching the key repos mentioned in the metadata:
- nucleus, mementum, gptel (explicitly mentioned)
- Also zeroclaw, context-mode, eca (from the topic performance)

I need to:
1. Fetch the GitHub pages for davidwuchn/* repos


2. Read their README/AGENTS files
3. Check recent commits
4. Extract patterns

Let me start with a web search to find the repos.
</think><think>Good, I have data from gptel and nucleus. Let me now fetch the other key repos: mementum, zeroclaw, and context-mode.
</think><think>Now let me read the specific AGENTS.md or README files for deeper patterns from the key repos. Let me check nucleus and gptel AGENTS.md files and also read the key parts of context-mode and zeroclaw.
</think><think>Now let me synthesize everything into a compact digest under 1200 chars. I have very rich material from:

Own repos:
1. **nucleus** (Emacs Lisp/EDN) - Lambda calculus notation, VSM system, Eight Keys (φμ∃∀τ), Wu Xing, OODA, modes (#=code, #=debug, etc.)
2. **gptel** (Emacs Lisp) - Tool definitions, MCP integration, multi-backend, in-place usage, introspection
3. **mementum** - Git-based memory protocol, feed-forward sessions, 3 storage types (working/memories/knowledge), 7 operations, human governance


4. **zeroclaw** (Rust) - Provider-agnostic runtime with fallback chains, workspace boundaries and security policy, tool receipts, SOP engine, ACP (JSON-RPC) for IDE integration
5. **context-mode** (TypeScript) - Context window optimization achieving 98% reduction through tool output sandboxing, session continuity via BM25 tracking, "Think in Code" paradigm, output compression
6. **eca** (Clojure) - Editor-agnostic protocol using LSP-inspired JSON-RPC, multi-model and multi-agent support, context with MCP resources

Now I'm distilling these architectural patterns into something concrete for an Emacs AI agent system under tight character constraints.
</think><think>Let me read the full context-mode README since it was stored in a temp file.
</think><think>Now I have comprehensive material from all four repos. Let me also fetch the GCP agent patterns for external reference.

Key patterns from own repos:
1. **gptel** - Tool definitions for agentic capabilities, MCP integration, multi-backend, "pause and resume" at intermediate stages
2. **nucleus** - Lambda calculus for AI cognition, attention priming via math symbols, OODA loops, 8 Keys principles
3. **mementum** - Git-based memory protocol, feed-forward sessions, 7 operations, human governance
4. **zeroclaw** - Provider-agnostic runtime, 30+ channels, fallback chains, workspace boundaries, cryptographic tool receipts


5. **context-mode** - Tool output sandboxing with 98% reduction, BM25 session continuity, "Think in Code" paradigm for context optimization

Now I'm looking at external agent patterns to round out the research.
</think><think>Let me search for GCP agent design patterns and other relevant external research.
</think><think>Now I have a comprehensive view of all four own repos plus the external references. Let me synthesize everything into a compact, actionable digest of under 1200 chars.

Key patterns from own repos:
1. **nucleus (Emacs Lisp)** - Mathematical symbol attention priming, lambda notation for AI cognition, VSM/Wu Xing framework, staged pipeline (research→assess→spec→code), Eight Keys principles
2. **gptel (Emacs Lisp)** - Tool-use protocol, MCP integration, multi-backend (curl/url-retrieve), multi-modal, introspection support, pause/resume capability
3. **mementum (multi-lang)** - Git as memory substrate, three storage types, seven operations, human governance (AI proposes, human approves, AI commits), feed-forward protocol


4. **zeroclaw (Rust)** - Provider-agnostic runtime with 30+ channel adapters, security-first architecture featuring workspace boundaries and tool receipts, SOP engine with fallback chains, and an ACP editor integration protocol
5. **context-mode (TypeScript)** - Sandboxes tool outputs to achieve 98% context reduction, uses BM25/FTS5 for session continuity across compaction events, and applies "Think in Code" principles to reduce tool calls 100x

From external sources, Google's agent design patterns include sequential pipelines, concurrent execution, and group chat orchestration for multi-agent systems. The external references show broader industry patterns—sequential, concurrent, and group-based orchestration from Google's ADK, plus academic frameworks around LLM-based multi-agent systems with specialized roles. I should now synthesize these into a compact digest that highlights what makes our approach distinct and actionable for the user's specific context.
</think>

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
