# Research: 2026-05-31 09:37

**Strategy:** persisted-findings
**Findings hash:** c6db56d577276e057db939c12680ee36789ec03f
**Targets:** lisp/modules/gptel-tools-agent-experiment-core.el
**Outcome:** 0/3 kept (0%)

**Raw Findings:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-31 09:09

Researcher result for task: External research turn 1/2

<think>
The user wants me to analyze their own repositories (davidwuchn/*) and produce a research digest with:
- 53% focus on own repos
- 15% external references
- Max 1200 chars
- Must start with their own repos

Let me fetch their repos and synthesize.
</think><think>
Now I have a comprehensive view of davidwuchn's repos. Let me also read the cached file for more context, and then fetch key READMEs from the most relevant repos.

Key own repos for AI agent patterns:
1. **zeroclaw** (Rust) - "Fast, small, fully autonomous AI personal assistant infrastructure"
2. **context-mode** (TypeScript) - "Context window optimization for AI coding agents. Sandboxes tool output, 98% reduction"
3. **eca** (Clojure) - "Editor Code Assistant - AI pair programming capabilities agnostic of editor"
4. **ai-code-interface.el** (Emacs Lisp) - "Unified Emacs interface supporting OpenAI Codex, GitHub Copilot CLI, Claude Code, Gemini CLI, Opencode"


5. **nullclaw** (Zig) - "Fastest, smallest, fully autonomous AI assistant infrastructure"
6. **Ori-Mnemos** (TypeScript) - "Local-first persistent agentic memory powered by Recursive Memory Harness (RMH)"

Now I'm diving into the READMEs for these repos to extract the architectural patterns they're implementing.
</think><think>
Now I have very good material. Let me also fetch the GCP design patterns and the arxiv paper for external references, then synthesize everything into a concise digest under 1200 chars.

Key own repos patterns:
1. **zeroclaw** (Rust) - Provider-agnostic agent runtime, multi-channel (30+ adapters), SOP engine, security policy, tool receipts, fallback chains, workspace boundaries, sandboxing
2. **context-mode** (TypeScript) - Context window optimization, 98% reduction by sandboxing tool output, session continuity tracking, output compression
3. **eca** (Clojure) - Editor-agnostic protocol (LSP-inspired), multi-model, multi-agent/subagent, context support, MCP resources


4. **nullclaw** (Zig) - Minimal AI infrastructure, "fully autonomous AI assistant"

Now I'm reviewing the GCP and arxiv references on agent orchestration patterns—sequential, concurrent, group chat, handoff, and magentic approaches—along with the decision model framework for selecting the right pattern based on task complexity and coordination needs. Let me synthesize these into the digest.
</think><think>
Now I have enough material to synthesize a comprehensive digest. Let me analyze the key patterns:

**Own Repos (davidwuchn/*) - 53% focus:**

1. **zeroclaw** (Rust) - Most comprehensive agent runtime:
   - Provider-agnostic: pluggable LLM backends
   - Multi-channel: 30+ adapters (Discord, Telegram, Matrix, etc.)
   - Agent loop + security policy + SOP engine
   - Fallback chains for provider reliability
   - Workspace boundaries + OS-level sandboxing (Landlock/Bubblewrap/Seatbelt)
   - Tool receipts (cryptographic verification)
   - Standard Operating Procedures (SOP engine) - event-triggered workflows
   - ACP - IDE integration via JSON-RPC over stdio
   - TOML configuration, gateway/dashboard

2. **nullclaw** (Zig) - Minimal infrastructure approach:
   - 678 KB static binary, ~1 MB RAM, <2ms startup
   - 50+ providers, 19 channels, 35+ tools, 10 memory engines
   - vtable interfaces for pluggability (providers, channels, tools, memory, peripherals)
   - Multi-layer sandbox (landlock, firejail, bubblewrap, docker)
   - Workspace scoping, encrypted secrets
   - MCP, subagents

3. **context-mode** focuses on reducing context overhead through aggressive filtering—sandboxing tool outputs to cut 315 KB down to 5.4 KB (98% savings), maintaining session continuity across edits and git operations, and trimming verbose responses with output compression.

4. **eca** (Clojure) provides an editor-agnostic protocol inspired by LSP, with support for multiple models, agents, subagents, MCP resources, and OpenTelemetry telemetry—structured around stdin/stdout communication.

5. **Ori-Mnemos** implements a persistent memory system using markdown files and wiki-links as a graph structure, with SQLite indexing and BM25 plus embedding plus PageRank for retrieval, achieving competitive results against Mem0 while avoiding cloud dependencies.

The key insight is that these systems converge on similar architectural principles despite different implementations.

Now I'm looking at external patterns from the arxiv paper on agent design patterns and GCP/Azure orchestration approaches—sequential, concurrent, group chat, handoff, and magentic patterns each suited for different task structures, plus a decision model framework for selecting the right approach. The common thread across all of them is provider abstraction, sandboxing as a core constraint, explicit session management, memory systems that persist across sessions, and security policies that define what the agent can and cannot do.
</think>

---

Researcher result for task: External research turn 2/2

The user wants me to perform an external research turn, focusing on novel AI agent patterns. Let me review what was found previously and then conduct new external searches.

Let me check the research memory first to understand what's been explored, then search for new external sources.

Key constraints:
- 100% external (per controller directive)
- Probe first: skim sources before deep-reading
- Max 1200 chars output
- Token budget: 4879
- Stop threshold: 66% confidence

Let me search for recent external sources across different platforms.Let me review the research memory and then probe fresh external sources.Good, I got several external sources. Let me now probe the most promising ones:

1. The arXiv paper on multi-agent orchestration (2601.13671v1) - this looks like it could have novel patterns
2. The Azure architecture guide on AI agent design patterns - practical patterns
3. The Google Cloud architecture doc - choose design pattern for agentic systems
4. The MCP.el + gptel integration blog post - directly Emacs-relevant

Let me probe these by fetching the most promising ones. I'll prioritize:
- arXiv paper (most novel, likely academic depth)
- Azure patterns (practical, implementable)
- MCP.el blog (Emacs-specific)
- gptel manual (to see if there are new patterns we haven't noted)Good external sources found. Let me probe the most promising ones for depth.Let me now read the key sections of the arXiv paper and the Azure patterns doc to extract actionable insights.Let me read the key sections of those large docs.Good, I'm getting solid material. Let me now read more from the Azure doc for the other patterns (concurrent, group chat, handoff, magentic) and also the arXiv paper sections on state management and error recovery. Let me also search for one more external source.Let me read the remaining orchestration patterns and search for one more novel source.I now have substantial material. Let me also read a bit more of the arXiv paper for the A2A protocol and error recovery/challenges section, and also look at the Azure doc for more patterns (group chat, handoff, magentic).

Actually, I think I have enough to synthesize. Let me check the token budget: I've used quite a lot but I should be within 4879. Let me synthesize my findings now.

Key external insights:

1. **Azure/AWS orchestration patterns spectrum**: Direct call → Single agent+Tools → Multi-agent orchestration. Key principle: "Use the lowest level of complexity that reliably meets requirements." Applies directly to our Emacs agent system: don't jump to multi-agent when a single agent with well-crafted tools suffices.

2. **Concurrent orchestration (fan-out/fan-in)**: Multiple specialized agents process same input in parallel, then aggregate. Could apply to our system by running code review, test generation, and documentation in parallel on the same buffer.

3. **Group chat orchestration**: Agents collaborate through shared conversation with a chat manager. This maps well to Emacs buffers - we could have multiple agent "voices" in different Emacs windows collaborating.

4. **ArXiv paper: Orchestration layer architecture**: Planning → Execution → State Management → Quality Ops. The separation of planning (what), policy (how rules), execution (run), state (checkpoints), and quality (validation) is a clean architecture we could adopt.

5. **ArXiv paper: State and Knowledge Management**: "Separation of operational state from knowledge state preserves modularity." This is directly applicable: our agent system should separate conversation state (operational) from domain knowledge (RAG/context).

6. **MCP.el + gptel integration**: The blog shows Emacs now has MCP capabilities through mcp.el, enabling external tool servers (web search, file access, GitHub ops). Our agent system could leverage mcp.el integration directly.

7. **Context engineering via gptel**: Branching context, topic restriction, editing LLM responses - these are patterns already available in gptel that our agent system should exploit rather than reinvent.

Now let me also check - what does our own agent system have, to avoid redundancy? Let me check the current codebase quickly.Let me quickly verify what our codebase already implements to avoid redundancy.7333 matches is way too many - these are probably matching in vendored packages. Let me narrow the search to our own code.7333 matches is way too many - these are probably matching in vendored packages. Let me narrow the search to our own code.Good - we already have:
- Programmatic tool orchestration (gptel-tools-programmatic.el)
- Sandbox for tool orchestration (gptel-sandbox.el)
- Benchmark for programmatic orchestration
- Auto-workflow evolution and research

We do NOT have:
- Concurrent/fan-out-fan-in agent pattern
- Group chat / multi-agent debate pattern
- State checkpoint and knowledge separation
- MCP.el integration
- Context branching for sessions

Let me now synthesize the final digest. I need to stay under ~1200 chars total and focus on actionable, novel patterns.

Let me now compose the final research digest.

**Digested Insights:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-31 09:09

Researcher result for task: External research turn 1/2

<think>
The user wants me to analyze their own repositories (davidwuchn/*) and produce a research digest with:
- 53% focus on own repos
- 15% external references
- Max 1200 chars
- Must start with their own repos

Let me fetch their repos and synthesize.
</think><think>
Now I have a comprehensive view of davidwuchn's repos. Let me also read the cached file for more context, and then fetch key READMEs from the most relevant repos.

Key own repos for AI agent patterns:
1. **zeroclaw** (Rust) - "Fast, small, fully autonomous AI personal assistant infrastructure"
2. **context-mode** (TypeScript) - "Context window optimization for AI coding agents. Sandboxes tool output, 98% reduction"
3. **eca** (Clojure) - "Editor Code Assistant - AI pair programming capabilities agnostic of editor"
4. **ai-code-interface.el** (Emacs Lisp) - "Unified Emacs interface supporting OpenAI Codex, GitHub Copilot CLI, Claude Code, Gemini CLI, Opencode"


5. **nullclaw** (Zig) - "Fastest, smallest, fully autonomous AI assistant infrastructure"
6. **Ori-Mnemos** (TypeScript) - "Local-first persistent agentic memory powered by Recursive Memory Harness (RMH)"

Now I'm diving into the READMEs for these repos to extract the architectural patterns they're implementing.
</think><think>
Now I have very good material. Let me also fetch the GCP design patterns and the arxiv paper for external references, then synthesize everything into a concise digest under 1200 chars.

Key own repos patterns:
1. **zeroclaw** (Rust) - Provider-agnostic agent runtime, multi-channel (30+ adapters), SOP engine, security policy, tool receipts, fallback chains, workspace boundaries, sandboxing
2. **context-mode** (TypeScript) - Context window optimization, 98% reduction by sandboxing tool output, session continuity tracking, output compression
3. **eca** (Clojure) - Editor-agnostic protocol (LSP-inspired), multi-model, multi-agent/subagent, context support, MCP resources


4. **nullclaw** (Zig) - Minimal AI infrastructure, "fully autonomous AI assistant"

Now I'm reviewing the GCP and arxiv references on agent orchestration patterns—sequential, concurrent, group chat, handoff, and magentic approaches—along with the decision model framework for selecting the right pattern based on task complexity and coordination needs. Let me synthesize these into the digest.
</think><think>
Now I have enough material to synthesize a comprehensive digest. Let me analyze the key patterns:

**Own Repos (davidwuchn/*) - 53% focus:**

1. **zeroclaw** (Rust) - Most comprehensive agent runtime:
   - Provider-agnostic: pluggable LLM backends
   - Multi-channel: 30+ adapters (Discord, Telegram, Matrix, etc.)
   - Agent loop + security policy + SOP engine
   - Fallback chains for provider reliability
   - Workspace boundaries + OS-level sandboxing (Landlock/Bubblewrap/Seatbelt)
   - Tool receipts (cryptographic verification)
   - Standard Operating Procedures (SOP engine) - event-triggered workflows
   - ACP - IDE integration via JSON-RPC over stdio
   - TOML configuration, gateway/dashboard

2. **nullclaw** (Zig) - Minimal infrastructure approach:
   - 678 KB static binary, ~1 MB RAM, <2ms startup
   - 50+ providers, 19 channels, 35+ tools, 10 memory engines
   - vtable interfaces for pluggability (providers, channels, tools, memory, peripherals)
   - Multi-layer sandbox (landlock, firejail, bubblewrap, docker)
   - Workspace scoping, encrypted secrets
   - MCP, subagents

3. **context-mode** focuses on reducing context overhead through aggressive filtering—sandboxing tool outputs to cut 315 KB down to 5.4 KB (98% savings), maintaining session continuity across edits and git operations, and trimming verbose responses with output compression.

4. **eca** (Clojure) provides an editor-agnostic protocol inspired by LSP, with support for multiple models, agents, subagents, MCP resources, and OpenTelemetry telemetry—structured around stdin/stdout communication.

5. **Ori-Mnemos** implements a persistent memory system using markdown files and wiki-links as a graph structure, with SQLite indexing and BM25 plus embedding plus PageRank for retrieval, achieving competitive results against Mem0 while avoiding cloud dependencies.

The key insight is that these systems converge on similar architectural principles despite different implementations.

Now I'm looking at external patterns from the arxiv paper on agent design patterns and GCP/Azure orchestration approaches—sequential, concurrent, group chat, handoff, and magentic patterns each suited for different task structures, plus a decision model framework for selecting the right approach. The common thread across all of them is provider abstraction, sandboxing as a core constraint, explicit session management, memory systems that persist across sessions, and security policies that define what the agent can and cannot do.
</think>

---

Researcher result for task: External research turn 2/2

The user wants me to perform an external research turn, focusing on novel AI agent patterns. Let me review what was found previously and then conduct new external searches.

Let me check the research memory first to understand what's been explored, then search for new external sources.

Key constraints:
- 100% external (per controller directive)
- Probe first: skim sources before deep-reading
- Max 1200 chars output
- Token budget: 4879
- Stop threshold: 66% confidence

Let me search for recent external sources across different platforms.Let me review the research memory and then probe fresh external sources.Good, I got several external sources. Let me now probe the most promising ones:

1. The arXiv paper on multi-agent orchestration (2601.13671v1) - this looks like it could have novel patterns
2. The Azure architecture guide on AI agent design patterns - practical patterns
3. The Google Cloud architecture doc - choose design pattern for agentic systems
4. The MCP.el + gptel integration blog post - directly Emacs-relevant

Let me probe these by fetching the most promising ones. I'll prioritize:
- arXiv paper (most novel, likely academic depth)
- Azure patterns (practical, implementable)
- MCP.el blog (Emacs-specific)
- gptel manual (to see if there are new patterns we haven't noted)Good external sources found. Let me probe the most promising ones for depth.Let me now read the key sections of the arXiv paper and the Azure patterns doc to extract actionable insights.Let me read the key sections of those large docs.Good, I'm getting solid material. Let me now read more from the Azure doc for the other patterns (concurrent, group chat, handoff, magentic) and also the arXiv paper sections on state management and error recovery. Let me also search for one more external source.Let me read the remaining orchestration patterns and search for one more novel source.I now have substantial material. Let me also read a bit more of the arXiv paper for the A2A protocol and error recovery/challenges section, and also look at the Azure doc for more patterns (group chat, handoff, magentic).

Actually, I think I have enough to synthesize. Let me check the token budget: I've used quite a lot but I should be within 4879. Let me synthesize my findings now.

Key external insights:

1. **Azure/AWS orchestration patterns spectrum**: Direct call → Single agent+Tools → Multi-agent orchestration. Key principle: "Use the lowest level of complexity that reliably meets requirements." Applies directly to our Emacs agent system: don't jump to multi-agent when a single agent with well-crafted tools suffices.

2. **Concurrent orchestration (fan-out/fan-in)**: Multiple specialized agents process same input in parallel, then aggregate. Could apply to our system by running code review, test generation, and documentation in parallel on the same buffer.

3. **Group chat orchestration**: Agents collaborate through shared conversation with a chat manager. This maps well to Emacs buffers - we could have multiple agent "voices" in different Emacs windows collaborating.

4. **ArXiv paper: Orchestration layer architecture**: Planning → Execution → State Management → Quality Ops. The separation of planning (what), policy (how rules), execution (run), state (checkpoints), and quality (validation) is a clean architecture we could adopt.

5. **ArXiv paper: State and Knowledge Management**: "Separation of operational state from knowledge state preserves modularity." This is directly applicable: our agent system should separate conversation state (operational) from domain knowledge (RAG/context).

6. **MCP.el + gptel integration**: The blog shows Emacs now has MCP capabilities through mcp.el, enabling external tool servers (web search, file access, GitHub ops). Our agent system could leverage mcp.el integration directly.

7. **Context engineering via gptel**: Branching context, topic restriction, editing LLM responses - these are patterns already available in gptel that our agent system should exploit rather than reinvent.

Now let me also check - what does our own agent system have, to avoid redundancy? Let me check the current codebase quickly.Let me quickly verify what our codebase already implements to avoid redundancy.7333 matches is way too many - these are probably matching in vendored packages. Let me narrow the search to our own code.7333 matches is way too many - these are probably matching in vendored packages. Let me narrow the search to our own code.Good - we already have:
- Programmatic tool orchestration (gptel-tools-programmatic.el)
- Sandbox for tool orchestration (gptel-sandbox.el)
- Benchmark for programmatic orchestration
- Auto-workflow evolution and research

We do NOT have:
- Concurrent/fan-out-fan-in agent pattern
- Group chat / multi-agent debate pattern
- State checkpoint and knowledge separation
- MCP.el integration
- Context branching for sessions

Let me now synthesize the final digest. I need to stay under ~1200 chars total and focus on actionable, novel patterns.

Let me now compose the final research digest.

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
