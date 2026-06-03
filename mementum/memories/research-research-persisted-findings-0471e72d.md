# Research: 2026-06-02 20:16

**Strategy:** persisted-findings
**Findings hash:** 0471e72d84798bb9e3b8810cea820d62b32efef2
**Targets:** lisp/modules/gptel-benchmark-subagent.el, lisp/modules/gptel-tools-agent-error.el
**Outcome:** 0/6 kept (0%)

**Raw Findings:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-02 19:16

Researcher result for task: External research turn 1/4

<think>
Let me analyze the context. The user wants me to produce a research digest focusing on their own repos (68% weight) with external references (21%), max 1200 chars, starting with their own repos.

Key constraints:
- 53%+ on own repos (they mention 53% in the latest prompt but the latest says 68%)
- 15% external references
- Max 1200 chars
- Must start with their own repos

From the cached data, I can see:
- Own repos: davidwuchn/zeroclaw, davidwuchn/context-mode, davidwuchn/eca, davidwuchn/nullclaw, etc.
- The agent's own internal state file mentions failure patterns like "AI agent workflow architectures (multi-step, state machines, planning)" and "Emacs Lisp AI integration patterns"


- They're asking for a research digest focused on their own repos (zeroclaw, context-mode, eca, nullclaw, ai-code-interface.el) with external references, max 1200 chars, starting with their own repos. Let me gather more context from these repositories to synthesize the key insights.
</think><think>
Now I have good data from the own repos. Let me also get the key architectural details from the stored files and from a few external references. Let me read the stored files for context-mode and nullclaw more carefully, and also fetch some external references.

Let me read the key parts of the stored files.
</think><think>
Now I have a very comprehensive understanding of the own repos. Let me synthesize the findings into a research digest under 1200 chars. The key patterns I see across the own repos are:

1. **Context Mode** - Context window optimization (sandboxing tool output, 98% reduction, session continuity via SQLite FTS5)
2. **ZeroClaw/NullClaw** - Provider-agnostic agent runtime, multi-channel (30+ adapters), SOP engine, security policy, tool receipts, fallback chains, workspace boundaries, sandboxing, hardware capable


3. **ECA** - Editor-agnostic protocol (LSP-inspired), multi-model, multi-agent/subagent, context support, MCP resources
4. **ai-code-interface.el** - Unified interface for AI coding CLIs, workflow portability

I'm noticing a clear pattern emerging: the repos consistently implement abstraction layers that decouple interfaces from providers, with context management and session continuity as core concerns. They're also converging on minimal binary footprints and sandboxed tool execution as fundamental design principles. Now I need to pull in a couple of external references to ground this synthesis.

I'm looking at multi-agent architectures and the Anthropic agent SDK patterns—specifically how handoffs, sequential workflows, and parallelization create coherent multi-agent systems. Let me pull in the Anthropic Patterns reference and synthesize everything into a concise digest under 1200 characters, keeping the focus on what I've built and how it connects to proven external patterns.
</think>

---

Researcher result for task: External research turn 2/4

<think>The user is asking me to do deep external discovery research on the davidwuchn repos. I have a rich context including:

1. The agent's internal state and research digest
2. Prior research results for multiple turns
3. References to own repos: zeroclaw, context-mode, eca, nullclaw, ai-code-interface.el, etc.

The agent state file tells me to:
- Start with own repos (high priority score 0.64)
- External references for 15% weight
- Max 1200 chars
- Build upon or contradict previous findings

Let me do a fresh web search for:
1. Recent developments on the own repos mentioned


2. External research on agent architectures for comparison

I'll search for recent commits and external research on agent design patterns in parallel.
</think><think>Now let me read the key READMEs for the own repos to get deep architectural insights.
</think><think>I have comprehensive data from all four own repos. Let me now also read the stored nullclaw and context-mode files for more details, and also fetch some external reference materials on AI agent patterns.

Now let me synthesize the findings. Let me read the key portions of the stored files.
</think><think>Now let me read more of the GCP design pattern and the nullclaw architecture file for deeper insights.
</think><think>Now I have a very comprehensive understanding of both the own repos AND the external patterns. Let me synthesize everything into a research digest under 1200 chars.

Key patterns from own repos:

1. **ZeroClaw** (Rust): Provider-agnostic agent runtime, 30+ channels, security-first with sandboxing, SOP engine, workspace boundaries, tool receipts, fallback chains
2. **Context Mode** (TypeScript): Context window optimization via sandboxing (98% reduction), session continuity via SQLite FTS5, "Think in Code" paradigm, routing enforcement
3. **ECA** (Clojure): Editor-agnostic protocol (LSP-inspired), multi-model, multi-agent/subagent, MCP resources


4. **NullClaw** (Zig): Compact footprint at 678KB with ~1MB RAM overhead, instant sub-2ms startup, hybrid in-memory search combining vector similarity and FTS5 through SQLite, fully swappable vtable interfaces for providers, channels, and tools, plus multi-layer sandboxing

External patterns from GCP:
- Sequential, parallel, loop, review/critique, and iterative refinement approaches to agent orchestration
- Context engineering and modular design principles

The core pattern emerging is that performance-critical systems benefit from tight integration—NullClaw demonstrates this with embedded vector search in SQLite using FTS5 BM25, achieving what distributed vector databases do locally. ZeroClaw and NullClaw both enforce security through layered defenses: workspace boundaries, tool receipts, and OS-level sandboxing rather than relying on a single mechanism. ECA's protocol design mirrors LSP's success, establishing a stable middle layer that abstracts model differences and creates portable, maintainable systems. Context Mode applies the "Think in Code" approach to reduce token overhead by executing JavaScript to compute results instead of loading them into the context window. Architecture - Every subsystem (provider, channel, memory, tool, sandbox, runtime, tunnel, etc.) is a vtable interface with multiple implementations. Swap with config, no code changes. This enables ZeroClaw/NullClaw's "fully swappable" architecture.
2. **Context sandboxing** - Raw tool output never enters context; sandboxing at the routing layer (not LLM layer) achieves 98% context reduction without behavioral constraints.
3. **Hybrid memory** - SQLite stores both FTS5 (BM25) and vector (BLOB + cosine) for context continuity when sessions compact, replacing external vector DBs.
4. **"Think in Code" paradigm** - Agents execute scripts (ctx_execute) for data processing tasks rather than reading many files, reducing 100x token overhead.
5. **Security depth** - Tool receipts + workspace boundaries + OS sandboxing + autonomy tiers = defense in depth for untrusted channels.

The vtable interface pattern is the biggest win here - it's how you make everything swappable without touching code, and I could apply this to the eca module's provider abstraction. The context sandboxing approach with routing enforcement is solid but would need some adaptation for Emacs since there's no native MCP server equivalent. The hybrid memory with FTS5 and vector search on SQLite is exactly what's needed for session continuity, and the "Think in Code" pattern could cut context overhead dramatically if I implement a sandboxed eval in Elisp. Security depth with tool receipts is the key insight for safe autonomous operation.
</think>

---

Researcher result for task: External research turn 3/4

<think>Now I have comprehensive data. Let me synthesize everything into the research digest under 1200 chars. Let me organize by source and extract non-obvious patterns.

Key patterns from own repos:

**ZeroClaw (Rust, zeroclaw)**:
1. Provider-agnostic agent runtime with 30+ adapters (multi-channel)
2. SOP (Standard Operating Procedure) engine - domain-specific procedures
3. Security policy and tool receipts (audit trail for tool execution)
4. Fallback chains - graceful degradation across providers
5. Workspace boundaries and sandboxing
6. Hardware capable (native tool use)


7. **Context-mode (TypeScript)**:
- Context window optimization via sandboxing tool output for 98% reduction
- Session continuity tracking and output compression
- SQLite FTS5 full-text search

**ECA (Clojure, eca)**:
1. Editor-agnostic protocol inspired by LSP
2. Multi-model and multi-agent/subagent orchestration
3. MCP resources integration and context support

**NullClaw (Zig, nullclaw)**:
1. Minimal infrastructure approach
2. Fully autonomous AI agent architecture

**AI Code Interface (Emacs Lisp, ai-code-interface.el)**:
1. Unified multi-provider interface
2. Session-based interaction

Now looking at external patterns emerging from research. Multi-agent orchestration is getting a lot of attention with handoff patterns where agents delegate through explicit API contracts, and group chat approaches like CAMEL for scalable communication. There's also growing focus on agent memory systems with hierarchical designs combining working, episodic, semantic, and procedural layers, plus the recursive memory harness concept for agentic memory.

I should look into how context window optimization with semantic compression might apply here, and dig into more papers on agent design patterns.
</think><think>Now let me fetch the key external sources for deep insights.
</think><think>Now I have excellent external data. Let me also read the stored Mem0 blog file for the full details.
</think><think>The file is too large. Let me get the middle portion with the key findings.
</think><think>Now I have a comprehensive picture. Let me synthesize everything into a concise research digest under 1200 chars.

Key patterns:

**From own repos:**
1. **Context Mode** — context window optimization via sandboxing tool output, session continuity (SQLite FTS5), 98% context reduction
2. **ZeroClaw/NullClaw** — provider-agnostic agent runtime, 30+ channel adapters, SOP engine, security policy enforcement, tool receipts, fallback chains, workspace boundaries, sandboxing
3. **ECA** — editor-agnostic protocol (LSP-inspired), multi-model, multi-agent/subagent, context support, MCP resources


4. **Ori Mnemos** — local markdown files with knowledge graph navigation instead of traditional databases, emphasizing relativity over isolated retrieval through recursive graph traversal
5. **ai-code-interface.el** — supporting OpenAI Codex, GitHub Copilot CLI, Claude Code, Gemini CLI, and Opencode

The external landscape shows agent memory emerging as a first-class architectural primitive with established benchmarks like LoCoMo and LongMemEval, plus emerging standards like MCP gaining significant enterprise traction.

The critical insight here is that Recursive Memory Harness fundamentally reframes memory from a database problem to an environment the model actively navigates — knowledge graphs as prerequisites, recursion for unresolved queries, and decay algorithms that reshape the graph over time. Ori Mnemos demonstrates this outperforms traditional RAG systems by a substantial margin.
</think>

---

Researcher result for task: External research turn 4/4

<think>Let me now synthesize all the gathered information into a concise research digest under 1200 chars. I need to:

1. Start with own repos findings (68% weight as specified in the latest directive)
2. Include external references (21%)
3. Max 1200 chars
4. Include actionable insights

Key patterns from own repos:
1. **Context Mode** - Context window optimization via sandboxing tool output (98% reduction), session continuity tracking with SQLite FTS5
2. **ZeroClaw/NullClaw** - Provider-agnostic agent runtime, SOP engine, security policy, tool receipts, fallback chains, workspace boundaries, sandboxing, hardware-capable


3. **ECA** - Editor-agnostic protocol (LSP-inspired), multi-model, multi-agent, MCP resources
4. **ai-code-interface.el** - Unified multi-provider interface

From external sources, I'm seeing GCP patterns like sequential execution, parallel fan-out with merge, and handoff delegation for multi-agent coordination. From arxiv, there's hierarchical task decomposition with a supervisor dispatching to specialized agents, along with decision frameworks for choosing between different agent patterns. Now I need to distill these into concrete patterns that can be applied directly.

I'm extracting three non-obvious insights: tool receipts work like receipts with provider + timestamp + cost metadata to enable rollback and retry; workspace boundaries constrain agents to safe directory paths with controlled escape hatches; and context mode sandboxes tool output separately from the conversation context to stay within token limits. I also see a sequential pattern emerging where zero-claw orchestrates tasks through a pipeline.

For the implementation side, I should leverage SQLite FTS5 to persist conversation state across sessions, use security policies to validate tool outputs and enforce workspace boundaries, apply tool receipts for rollback/retry mechanisms, and consider whether ECA's MCP protocol could handle tool output sandboxing in real-time. Now I'm drafting a concise digest under 1200 characters that captures these patterns with specific code references.

I need to verify that the external sources are genuinely different from what was already searched, so let me refocus on finding novel approaches to context optimization and agent orchestration that weren't covered in prior attempts. I'm synthesizing the findings into actionable patterns for the project. The key insights are that context mode uses SQLite FTS5 to compress tool outputs separately from the conversation context, zeroclaw implements workspace boundaries to constrain agent operations, and both systems leverage tool receipts to capture metadata for retry and fallback mechanisms. I should explore MCP integration for real-time tool output handling, persist agent state across sessions, and develop policies to validate outputs within constrained workspaces.
</think><think>Good. Now let me fetch the GCP agent patterns from their main website and also try the arxiv paper. Let me try the GCP agent patterns from the web search results, and the relevant arxiv paper about agent patterns.
</think><think>Good, I have the context-mode README loaded. Let me now read the full file and get the zeroclaw README, then synthesize everything into the 1200-char digest.
</think><think>Now I have excellent information. Let me synthesize:

Own repos key patterns:
1. **context-mode** (by mksglu, NOT davidwuchn - the README says "mksglu/context-mode" - but the memory file says davidwuchn/context-mode. Actually looking more carefully, the stored file says it's a different repo. But the cached memory from the internal agent state file at line 3 says "davidwuchn/context-mode" - let me check. Actually the README at raw.githubusercontent.com/davidwuchn/context-mode/main/README.md failed to load (404). The README I got via WebFetch is from mksglu/context-mode. But wait, the internal agent state file mentioned davidwuchn/context-mode. 

I need to reconcile this discrepancy - the WebFetch returned a README from mksglu/context-mode, but the agent state mentioned davidwuchn/context-mode as a different, zero-based solution. Let me check which one is actually the right one. Looking at the architecture differences between context-mode's MCP server approach and ECA's LSP-inspired design, I should also explore what nullclaw and zeroclaw bring to the table for a more comprehensive picture of the ecosystem.
</think><think>Now let me fetch the ZeroClaw docs and the NullClaw boilerplate docs, plus the arxiv paper on multi-agent orchestration.
</think><think>Now I have a comprehensive picture. Let me synthesize:

## Own Repos (key patterns):

1. **context-mode** (mksglu, not davidwuchn - but used heavily by davidwuchn's ecosystem):
   - Hook-based tool interception (PreToolUse, PostToolUse, PreCompact, SessionStart)
   - Context sandboxing: raw tool output → 98% reduction (315KB→5.4KB)
   - SQLite FTS5 for session continuity across compactions
   - "Think in Code" paradigm: LLM as code generator, not data processor
   - BM25 retrieval for session resume
   - Cross-platform hooks system (Claude Code, Gemini CLI, VS Code, Cursor, OpenCode, KiloCode, JetBrains)

2. **ZeroClaw** (zeroclaw-labs):
   - Provider-agnostic agent runtime (Rust binary)
   - Multi-channel: 20+ (Discord, Telegram, Matrix, email, voice, webhooks, CLI)
   - Multi-provider: Anthropic, OpenAI, Ollama, ~20 others
   - SOP engine for workflow definition
   - Security policy + tool receipts
   - Fallback chains
   - Workspace boundaries
   - Sandboxing
   - OpenTelemetry

3. **ECA** (Editor Code Assistant):
   - Editor-agnostic protocol (LSP-inspired)
   - Multi-model support
   - Multi-agent/subagent
   - Context support including MCP resources
   - stdin/stdout communication
   - OpenTelemetry metrics
   - Clojure implementation

4. **NullClaw**:
   - Zig binary at 678KB running in 1MB RAM with 2ms boot time
   - 33 tool_name values and 20 channels available
   - 9 different memory backends supported
   - Capability catalog with channel and provider routing
   - Full autonomous infrastructure with security and workspace features

5. **nullboiler**:
   - Multi-step AI agent workflow orchestration
   - Execution graphs, shared state management, and work dispatch to agents
   - Checkpointing with streaming support

Looking at external patterns now, there's a strong focus on the orchestration layer as the control plane for multi-agent systems—it handles agent specialization and the technical mechanisms that coordinate them.

For single agent scenarios, ZeroClaw takes a SOP engine approach with tool receipts and fallback chains. The ECA protocol maps directly to LSP's editor-agnostic stdin/stdout design, and NullClaw's minimal footprint is a notable competitive advantage. There's also the dynamic orchestration framework from OpenReview that uses a centralized, context-aware orchestrator to activate agents flexibly.

For practical application, I could bring ECA's LSP-inspired approach to ai-code-interface.el, adapt NullClaw's memory backend registry for the agent system, implement context-mode's hook interception for the gptel pipeline, leverage context-mode's "Think in Code" paradigm for expensive operations, and apply ZeroClaw's tool receipts concept to track each tool's execution provenance. I need to keep this concise and prioritize the strongest insights for implementation.

Now I'm extracting the most impactful findings to distill down to 1200 characters.
</think><think>Let me read the orchestration layer section from the arxiv paper.
</think><think>Now I have very rich material. Let me synthesize the key findings:

## Own Repos Patterns

1. **Context Mode** (TypeScript): Context window optimization via sandboxing (tool output goes to SQLite FTS5, not context). 98% reduction. Session continuity via BM25 search. "Think in Code" paradigm — LLM writes scripts to process data, not read data directly.

2. **ZeroClaw** (Rust): Agent runtime with provider-agnostic model abstraction, 20+ channel adapters (Discord, Telegram, Matrix, email, voice, webhooks), SOP workflow engine, security policy enforcement, tool receipts, fallback chains, workspace boundaries, sandboxing. "personal AI assistant you own."


3. **NullClaw** (Zig): Minimal 678 KB binary footprint, 1 MB RAM footprint, 2ms boot time. 89 provider aliases, 33 unique tools, 20 channel adapters. No runtime layer — compiled Zig.
4. **ECA** (Clojure): Editor-agnostic protocol inspired by LSP, handling multi-model and multi-agent/subagent coordination, with context support including MCP resources. Protocol-driven design for extensibility.
5. **nullboiler**: Multi-step AI agent workflow orchestration through execution graphs, shared state management, agent dispatch, and checkpoint streaming.
6. **ai-code-interface.el** (Emacs Lisp): Unified interface aggregating OpenAI Codex, GitHub Copilot CLI, Claude Code, Gemini CLI, and Opencode.

Looking at the academic literature, I'm seeing architectural patterns around multi-agent systems with worker, service, and support agents working in coordinated layers. The orchestration control plane handles planning, policy management, execution control, state management, and quality assurance. There's also the MCP protocol for external tool and context access, alongside emerging standards like A2A for agent-to-agent communication and enterprise frameworks like Agent OS from PwC and Trusted Agent Huddle from Accenture. Observability is being built through OpenTelemetry-style tracing, model versioning, and deterministic replay mechanisms.

Now I'm synthesizing these concepts into a comprehensive digest that captures the full architecture.
</think>

**Digested Insights:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-02 19:16

Researcher result for task: External research turn 1/4

<think>
Let me analyze the context. The user wants me to produce a research digest focusing on their own repos (68% weight) with external references (21%), max 1200 chars, starting with their own repos.

Key constraints:
- 53%+ on own repos (they mention 53% in the latest prompt but the latest says 68%)
- 15% external references
- Max 1200 chars
- Must start with their own repos

From the cached data, I can see:
- Own repos: davidwuchn/zeroclaw, davidwuchn/context-mode, davidwuchn/eca, davidwuchn/nullclaw, etc.
- The agent's own internal state file mentions failure patterns like "AI agent workflow architectures (multi-step, state machines, planning)" and "Emacs Lisp AI integration patterns"


- They're asking for a research digest focused on their own repos (zeroclaw, context-mode, eca, nullclaw, ai-code-interface.el) with external references, max 1200 chars, starting with their own repos. Let me gather more context from these repositories to synthesize the key insights.
</think><think>
Now I have good data from the own repos. Let me also get the key architectural details from the stored files and from a few external references. Let me read the stored files for context-mode and nullclaw more carefully, and also fetch some external references.

Let me read the key parts of the stored files.
</think><think>
Now I have a very comprehensive understanding of the own repos. Let me synthesize the findings into a research digest under 1200 chars. The key patterns I see across the own repos are:

1. **Context Mode** - Context window optimization (sandboxing tool output, 98% reduction, session continuity via SQLite FTS5)
2. **ZeroClaw/NullClaw** - Provider-agnostic agent runtime, multi-channel (30+ adapters), SOP engine, security policy, tool receipts, fallback chains, workspace boundaries, sandboxing, hardware capable


3. **ECA** - Editor-agnostic protocol (LSP-inspired), multi-model, multi-agent/subagent, context support, MCP resources
4. **ai-code-interface.el** - Unified interface for AI coding CLIs, workflow portability

I'm noticing a clear pattern emerging: the repos consistently implement abstraction layers that decouple interfaces from providers, with context management and session continuity as core concerns. They're also converging on minimal binary footprints and sandboxed tool execution as fundamental design principles. Now I need to pull in a couple of external references to ground this synthesis.

I'm looking at multi-agent architectures and the Anthropic agent SDK patterns—specifically how handoffs, sequential workflows, and parallelization create coherent multi-agent systems. Let me pull in the Anthropic Patterns reference and synthesize everything into a concise digest under 1200 characters, keeping the focus on what I've built and how it connects to proven external patterns.
</think>

---

Researcher result for task: External research turn 2/4

<think>The user is asking me to do deep external discovery research on the davidwuchn repos. I have a rich context including:

1. The agent's internal state and research digest
2. Prior research results for multiple turns
3. References to own repos: zeroclaw, context-mode, eca, nullclaw, ai-code-interface.el, etc.

The agent state file tells me to:
- Start with own repos (high priority score 0.64)
- External references for 15% weight
- Max 1200 chars
- Build upon or contradict previous findings

Let me do a fresh web search for:
1. Recent developments on the own repos mentioned


2. External research on agent architectures for comparison

I'll search for recent commits and external research on agent design patterns in parallel.
</think><think>Now let me read the key READMEs for the own repos to get deep architectural insights.
</think><think>I have comprehensive data from all four own repos. Let me now also read the stored nullclaw and context-mode files for more details, and also fetch some external reference materials on AI agent patterns.

Now let me synthesize the findings. Let me read the key portions of the stored files.
</think><think>Now let me read more of the GCP design pattern and the nullclaw architecture file for deeper insights.
</think><think>Now I have a very comprehensive understanding of both the own repos AND the external patterns. Let me synthesize everything into a research digest under 1200 chars.

Key patterns from own repos:

1. **ZeroClaw** (Rust): Provider-agnostic agent runtime, 30+ channels, security-first with sandboxing, SOP engine, workspace boundaries, tool receipts, fallback chains
2. **Context Mode** (TypeScript): Context window optimization via sandboxing (98% reduction), session continuity via SQLite FTS5, "Think in Code" paradigm, routing enforcement
3. **ECA** (Clojure): Editor-agnostic protocol (LSP-inspired), multi-model, multi-agent/subagent, MCP resources


4. **NullClaw** (Zig): Compact footprint at 678KB with ~1MB RAM overhead, instant sub-2ms startup, hybrid in-memory search combining vector similarity and FTS5 through SQLite, fully swappable vtable interfaces for providers, channels, and tools, plus multi-layer sandboxing

External patterns from GCP:
- Sequential, parallel, loop, review/critique, and iterative refinement approaches to agent orchestration
- Context engineering and modular design principles

The core pattern emerging is that performance-critical systems benefit from tight integration—NullClaw demonstrates this with embedded vector search in SQLite using FTS5 BM25, achieving what distributed vector databases do locally. ZeroClaw and NullClaw both enforce security through layered defenses: workspace boundaries, tool receipts, and OS-level sandboxing rather than relying on a single mechanism. ECA's protocol design mirrors LSP's success, establishing a stable middle layer that abstracts model differences and creates portable, maintainable systems. Context Mode applies the "Think in Code" approach to reduce token overhead by executing JavaScript to compute results instead of loading them into the context window. Architecture - Every subsystem (provider, channel, memory, tool, sandbox, runtime, tunnel, etc.) is a vtable interface with multiple implementations. Swap with config, no code changes. This enables ZeroClaw/NullClaw's "fully swappable" architecture.
2. **Context sandboxing** - Raw tool output never enters context; sandboxing at the routing layer (not LLM layer) achieves 98% context reduction without behavioral constraints.
3. **Hybrid memory** - SQLite stores both FTS5 (BM25) and vector (BLOB + cosine) for context continuity when sessions compact, replacing external vector DBs.
4. **"Think in Code" paradigm** - Agents execute scripts (ctx_execute) for data processing tasks rather than reading many files, reducing 100x token overhead.
5. **Security depth** - Tool receipts + workspace boundaries + OS sandboxing + autonomy tiers = defense in depth for untrusted channels.

The vtable interface pattern is the biggest win here - it's how you make everything swappable without touching code, and I could apply this to the eca module's provider abstraction. The context sandboxing approach with routing enforcement is solid but would need some adaptation for Emacs since there's no native MCP server equivalent. The hybrid memory with FTS5 and vector search on SQLite is exactly what's needed for session continuity, and the "Think in Code" pattern could cut context overhead dramatically if I implement a sandboxed eval in Elisp. Security depth with tool receipts is the key insight for safe autonomous operation.
</think>

---

Researcher result for task: External research turn 3/4

<think>Now I have comprehensive data. Let me synthesize everything into the research digest under 1200 chars. Let me organize by source and extract non-obvious patterns.

Key patterns from own repos:

**ZeroClaw (Rust, zeroclaw)**:
1. Provider-agnostic agent runtime with 30+ adapters (multi-channel)
2. SOP (Standard Operating Procedure) engine - domain-specific procedures
3. Security policy and tool receipts (audit trail for tool execution)
4. Fallback chains - graceful degradation across providers
5. Workspace boundaries and sandboxing
6. Hardware capable (native tool use)


7. **Context-mode (TypeScript)**:
- Context window optimization via sandboxing tool output for 98% reduction
- Session continuity tracking and output compression
- SQLite FTS5 full-text search

**ECA (Clojure, eca)**:
1. Editor-agnostic protocol inspired by LSP
2. Multi-model and multi-agent/subagent orchestration
3. MCP resources integration and context support

**NullClaw (Zig, nullclaw)**:
1. Minimal infrastructure approach
2. Fully autonomous AI agent architecture

**AI Code Interface (Emacs Lisp, ai-code-interface.el)**:
1. Unified multi-provider interface
2. Session-based interaction

Now looking at external patterns emerging from research. Multi-agent orchestration is getting a lot of attention with handoff patterns where agents delegate through explicit API contracts, and group chat approaches like CAMEL for scalable communication. There's also growing focus on agent memory systems with hierarchical designs combining working, episodic, semantic, and procedural layers, plus the recursive memory harness concept for agentic memory.

I should look into how context window optimization with semantic compression might apply here, and dig into more papers on agent design patterns.
</think><think>Now let me fetch the key external sources for deep insights.
</think><think>Now I have excellent external data. Let me also read the stored Mem0 blog file for the full details.
</think><think>The file is too large. Let me get the middle portion with the key findings.
</think><think>Now I have a comprehensive picture. Let me synthesize everything into a concise research digest under 1200 chars.

Key patterns:

**From own repos:**
1. **Context Mode** — context window optimization via sandboxing tool output, session continuity (SQLite FTS5), 98% context reduction
2. **ZeroClaw/NullClaw** — provider-agnostic agent runtime, 30+ channel adapters, SOP engine, security policy enforcement, tool receipts, fallback chains, workspace boundaries, sandboxing
3. **ECA** — editor-agnostic protocol (LSP-inspired), multi-model, multi-agent/subagent, context support, MCP resources


4. **Ori Mnemos** — local markdown files with knowledge graph navigation instead of traditional databases, emphasizing relativity over isolated retrieval through recursive graph traversal
5. **ai-code-interface.el** — supporting OpenAI Codex, GitHub Copilot CLI, Claude Code, Gemini CLI, and Opencode

The external landscape shows agent memory emerging as a first-class architectural primitive with established benchmarks like LoCoMo and LongMemEval, plus emerging standards like MCP gaining significant enterprise traction.

The critical insight here is that Recursive Memory Harness fundamentally reframes memory from a database problem to an environment the model actively navigates — knowledge graphs as prerequisites, recursion for unresolved queries, and decay algorithms that reshape the graph over time. Ori Mnemos demonstrates this outperforms traditional RAG systems by a substantial margin.
</think>

---

Researcher result for task: External research turn 4/4

<think>Let me now synthesize all the gathered information into a concise research digest under 1200 chars. I need to:

1. Start with own repos findings (68% weight as specified in the latest directive)
2. Include external references (21%)
3. Max 1200 chars
4. Include actionable insights

Key patterns from own repos:
1. **Context Mode** - Context window optimization via sandboxing tool output (98% reduction), session continuity tracking with SQLite FTS5
2. **ZeroClaw/NullClaw** - Provider-agnostic agent runtime, SOP engine, security policy, tool receipts, fallback chains, workspace boundaries, sandboxing, hardware-capable


3. **ECA** - Editor-agnostic protocol (LSP-inspired), multi-model, multi-agent, MCP resources
4. **ai-code-interface.el** - Unified multi-provider interface

From external sources, I'm seeing GCP patterns like sequential execution, parallel fan-out with merge, and handoff delegation for multi-agent coordination. From arxiv, there's hierarchical task decomposition with a supervisor dispatching to specialized agents, along with decision frameworks for choosing between different agent patterns. Now I need to distill these into concrete patterns that can be applied directly.

I'm extracting three non-obvious insights: tool receipts work like receipts with provider + timestamp + cost metadata to enable rollback and retry; workspace boundaries constrain agents to safe directory paths with controlled escape hatches; and context mode sandboxes tool output separately from the conversation context to stay within token limits. I also see a sequential pattern emerging where zero-claw orchestrates tasks through a pipeline.

For the implementation side, I should leverage SQLite FTS5 to persist conversation state across sessions, use security policies to validate tool outputs and enforce workspace boundaries, apply tool receipts for rollback/retry mechanisms, and consider whether ECA's MCP protocol could handle tool output sandboxing in real-time. Now I'm drafting a concise digest under 1200 characters that captures these patterns with specific code references.

I need to verify that the external sources are genuinely different from what was already searched, so let me refocus on finding novel approaches to context optimization and agent orchestration that weren't covered in prior attempts. I'm synthesizing the findings into actionable patterns for the project. The key insights are that context mode uses SQLite FTS5 to compress tool outputs separately from the conversation context, zeroclaw implements workspace boundaries to constrain agent operations, and both systems leverage tool receipts to capture metadata for retry and fallback mechanisms. I should explore MCP integration for real-time tool output handling, persist agent state across sessions, and develop policies to validate outputs within constrained workspaces.
</think><think>Good. Now let me fetch the GCP agent patterns from their main website and also try the arxiv paper. Let me try the GCP agent patterns from the web search results, and the relevant arxiv paper about agent patterns.
</think><think>Good, I have the context-mode README loaded. Let me now read the full file and get the zeroclaw README, then synthesize everything into the 1200-char digest.
</think><think>Now I have excellent information. Let me synthesize:

Own repos key patterns:
1. **context-mode** (by mksglu, NOT davidwuchn - the README says "mksglu/context-mode" - but the memory file says davidwuchn/context-mode. Actually looking more carefully, the stored file says it's a different repo. But the cached memory from the internal agent state file at line 3 says "davidwuchn/context-mode" - let me check. Actually the README at raw.githubusercontent.com/davidwuchn/context-mode/main/README.md failed to load (404). The README I got via WebFetch is from mksglu/context-mode. But wait, the internal agent state file mentioned davidwuchn/context-mode. 

I need to reconcile this discrepancy - the WebFetch returned a README from mksglu/context-mode, but the agent state mentioned davidwuchn/context-mode as a different, zero-based solution. Let me check which one is actually the right one. Looking at the architecture differences between context-mode's MCP server approach and ECA's LSP-inspired design, I should also explore what nullclaw and zeroclaw bring to the table for a more comprehensive picture of the ecosystem.
</think><think>Now let me fetch the ZeroClaw docs and the NullClaw boilerplate docs, plus the arxiv paper on multi-agent orchestration.
</think><think>Now I have a comprehensive picture. Let me synthesize:

## Own Repos (key patterns):

1. **context-mode** (mksglu, not davidwuchn - but used heavily by davidwuchn's ecosystem):
   - Hook-based tool interception (PreToolUse, PostToolUse, PreCompact, SessionStart)
   - Context sandboxing: raw tool output → 98% reduction (315KB→5.4KB)
   - SQLite FTS5 for session continuity across compactions
   - "Think in Code" paradigm: LLM as code generator, not data processor
   - BM25 retrieval for session resume
   - Cross-platform hooks system (Claude Code, Gemini CLI, VS Code, Cursor, OpenCode, KiloCode, JetBrains)

2. **ZeroClaw** (zeroclaw-labs):
   - Provider-agnostic agent runtime (Rust binary)
   - Multi-channel: 20+ (Discord, Telegram, Matrix, email, voice, webhooks, CLI)
   - Multi-provider: Anthropic, OpenAI, Ollama, ~20 others
   - SOP engine for workflow definition
   - Security policy + tool receipts
   - Fallback chains
   - Workspace boundaries
   - Sandboxing
   - OpenTelemetry

3. **ECA** (Editor Code Assistant):
   - Editor-agnostic protocol (LSP-inspired)
   - Multi-model support
   - Multi-agent/subagent
   - Context support including MCP resources
   - stdin/stdout communication
   - OpenTelemetry metrics
   - Clojure implementation

4. **NullClaw**:
   - Zig binary at 678KB running in 1MB RAM with 2ms boot time
   - 33 tool_name values and 20 channels available
   - 9 different memory backends supported
   - Capability catalog with channel and provider routing
   - Full autonomous infrastructure with security and workspace features

5. **nullboiler**:
   - Multi-step AI agent workflow orchestration
   - Execution graphs, shared state management, and work dispatch to agents
   - Checkpointing with streaming support

Looking at external patterns now, there's a strong focus on the orchestration layer as the control plane for multi-agent systems—it handles agent specialization and the technical mechanisms that coordinate them.

For single agent scenarios, ZeroClaw takes a SOP engine approach with tool receipts and fallback chains. The ECA protocol maps directly to LSP's editor-agnostic stdin/stdout design, and NullClaw's minimal footprint is a notable competitive advantage. There's also the dynamic orchestration framework from OpenReview that uses a centralized, context-aware orchestrator to activate agents flexibly.

For practical application, I could bring ECA's LSP-inspired approach to ai-code-interface.el, adapt NullClaw's memory backend registry for the agent system, implement context-mode's hook interception for the gptel pipeline, leverage context-mode's "Think in Code" paradigm for expensive operations, and apply ZeroClaw's tool receipts concept to track each tool's execution provenance. I need to keep this concise and prioritize the strongest insights for implementation.

Now I'm extracting the most impactful findings to distill down to 1200 characters.
</think><think>Let me read the orchestration layer section from the arxiv paper.
</think><think>Now I have very rich material. Let me synthesize the key findings:

## Own Repos Patterns

1. **Context Mode** (TypeScript): Context window optimization via sandboxing (tool output goes to SQLite FTS5, not context). 98% reduction. Session continuity via BM25 search. "Think in Code" paradigm — LLM writes scripts to process data, not read data directly.

2. **ZeroClaw** (Rust): Agent runtime with provider-agnostic model abstraction, 20+ channel adapters (Discord, Telegram, Matrix, email, voice, webhooks), SOP workflow engine, security policy enforcement, tool receipts, fallback chains, workspace boundaries, sandboxing. "personal AI assistant you own."


3. **NullClaw** (Zig): Minimal 678 KB binary footprint, 1 MB RAM footprint, 2ms boot time. 89 provider aliases, 33 unique tools, 20 channel adapters. No runtime layer — compiled Zig.
4. **ECA** (Clojure): Editor-agnostic protocol inspired by LSP, handling multi-model and multi-agent/subagent coordination, with context support including MCP resources. Protocol-driven design for extensibility.
5. **nullboiler**: Multi-step AI agent workflow orchestration through execution graphs, shared state management, agent dispatch, and checkpoint streaming.
6. **ai-code-interface.el** (Emacs Lisp): Unified interface aggregating OpenAI Codex, GitHub Copilot CLI, Claude Code, Gemini CLI, and Opencode.

Looking at the academic literature, I'm seeing architectural patterns around multi-agent systems with worker, service, and support agents working in coordinated layers. The orchestration control plane handles planning, policy management, execution control, state management, and quality assurance. There's also the MCP protocol for external tool and context access, alongside emerging standards like A2A for agent-to-agent communication and enterprise frameworks like Agent OS from PwC and Trusted Agent Huddle from Accenture. Observability is being built through OpenTelemetry-style tracing, model versioning, and deterministic replay mechanisms.

Now I'm synthesizing these concepts into a comprehensive digest that captures the full architecture.
</think>

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
