# Research: 2026-06-02 20:25

**Strategy:** persisted-findings
**Findings hash:** 47f962777a9b1a8d3134d1237aba1e377f8620e8
**Targets:** lisp/modules/gptel-benchmark-principles.el
**Outcome:** 0/3 kept (0%)

**Raw Findings:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-06-02 18:57

Researcher result for task: External research turn 1/3

<think>The user wants me to do deep external research, synthesizing findings from the provided project context and external sources. Let me analyze what's been provided and synthesize a comprehensive digest.

Key sources already provided:

**Own Repos (davidwuchn/*):**
1. **zeroclaw** (Rust, 2025-09-28) - Provider-agnostic agent runtime, multi-channel (30+ adapters), SOP engine, security policy, tool receipts, fallback chains, workspace boundaries, sandboxing. 7 open issues showing active development.

2. **context-mode** (TypeScript, 2025-09-28) - Context window optimization for AI coding agents. 98% reduction in token usage by sandboxing tool output. 

3. **eca** (Clojure, 2024-11-10) - Editor Code Assistant with editor-agnostic AI pair programming using LSP-inspired protocols, multi-model support, multi-agent orchestration, and MCP resource integration. 6 open issues tracking feature requests.

4. **ai-code-interface.el** (Emacs Lisp, 2025-08-13) - A unified Emacs interface that abstracts over multiple AI providers (OpenAI Codex, GitHub Copilot CLI, Claude Code, Gemini CLI, Opencode).

5. **nullclaw** (Zig, 2025-03-15) - Fastest, smallest fully autonomous AI assistant infrastructure written in Zig.

6. **Ori-Mnemos** (TypeScript, 2025-07-19) - Local-first persistent agentic memory powered by Recursive Memory Harness (RMH).

7. **gptel-auto-workflow** (Emacs Lisp, 2024-11-15) - Automated code improvement through hypothesis-driven experimentation and self-evolution.

8. **gptel-rag** (Emacs Lisp, 2025-04-02) - RAG system using vector embeddings with cosine similarity for semantic search.

9. **auto-workflow-research** (Emacs Lisp, 2024-11-15) - External research digestion for AutoTTS.

10. **context-agent** (TypeScript, 2025-01-27) - Context window optimization for Claude Code.

11. **gptel-auto-benchmark** (Emacs Lisp, 2024-11-15) - LLM prompt benchmarking with Wu Xing phase analysis.

12. **nucleus-agents** (Emacs Lisp, 2025-03-25) - Self-improving AI agents for nucleus.

13. **gptel-nucleus** (Emacs Lisp, 2025-08-31) - GPTel integration with nucleus.

14. **nucleus-prompts** (Emacs Lisp, 2025-09-13) - Core nucleus prompts infrastructure.

15. **nucleus** (Emacs Lisp, 2025-09-21) - Self-evolution harness for AI-assisted coding.

16. **gptel-auto-context** (Emacs Lisp, 2025-07-28) - Context compression for gptel.

17. **gptel-auto-chain** (Emacs Lisp, 2025-09-23) - Chain of thought for GPTel prompts.

18. **gptel-completion-n

I'm cataloging a suite of Emacs-based tools for AI orchestration—benchmarking, self-evolution, context management, and prompt engineering—alongside integrations like nucleus-prompts and gptel-nucleus that form the core infrastructure for adaptive AI workflows. I'm seeing a taxonomy of agent patterns from Google's research—sequential work, concurrent execution, group coordination, handoff protocols, and magentic systems that let multiple agents work together with shared context. There's also a decision framework for picking the right orchestration strategy based on task complexity and whether you need multi-agent coordination, plus architectural advice from Google's agent documentation on maintaining clean separation between the agent logic, tools, and model layer.

I'm noticing that provider abstraction patterns like zeroclaw and eca are working well in our codebase, so I should apply that thinking to how we structure agent runtimes. MCP is emerging as a standard for tool integration that both eca and nullclaw have adopted, and we're tracking source effectiveness through aligned ratios and quality metrics in AutoTTS. There's a tension I'm hitting though—AutoTTS metrics show our own repos are performing at 0.71 alignment while external sources are at 0.31, yet the system keeps pushing 16% external allocation, which doesn't add up. I need to reconcile what the metrics are actually telling me versus what the directive is enforcing.
</think><think>Let me search for these topics.
</think><think>Let me fetch the Google Research article and the Azure patterns guide, plus the InfoQ summary for concrete examples.
</think><think>Now I have very rich material. Let me synthesize the key findings from both own repos and external sources, then produce a deep research digest within 1200 chars. Let me structure it carefully.

Key external findings:
1. **Azure AI Agent Design Patterns** - 3-level complexity spectrum: Direct model call → Single agent with tools → Multiagent orchestration. Key insight: start with lowest complexity that reliably meets requirements.
2. **Google Research "Science of Scaling Agent Systems"** - 180 configs, 5 architectures. Key quantitative insights:
   - Multi-agent coordination improves parallelizable tasks by up to +81%
   - Multi-agent degrades sequential tasks by -39-70%


3. **Error amplification patterns** - Independent systems amplify errors 17.2x while centralized ones only amplify 4.4x, suggesting the orchestrator acts as a validation bottleneck.

My own architecture patterns reveal strong parallels: zeroclaw uses centralized orchestration with tool receipts and fallback chains; eca has an editor-agnostic multi-model setup; gptel-auto-workflow self-evolves through hypothesis-driven loops; context-mode compresses output for optimization; ai-code-interface abstracts providers; Ori-Mnemos provides memory; nucleus orchestrates agents with AutoTTS. Now I need to distill this into a deep research digest.

The core insight is that my architecture mirrors proven patterns—centralized orchestration aligns with what minimizes error amplification, while the self-evolution approach matches empirical findings that smarter models accelerate success when architecture is right. I should flag that my independent systems without feedback loops are risky, and I need to add decomposability checks before invoking multi-agent patterns. Let me synthesize this under 1200 characters.
</think><think>Now I have all the material I need. Let me synthesize a comprehensive deep research digest. I need to:

1. Start with own repos (91% weight based on AutoTTS score)
2. Include 1-2 external references
3. Max 1200 chars
4. Prefix with `[deep-external]`
5. Non-obvious architectural insights
6. Avoid re-reporting things already in the context

Let me now produce the synthesis. I need to be concise and focused, under 1200 characters.

Key synthesis points:


My architecture maps directly to proven enterprise patterns—zeroclaw's centralized hub-and-spoke with tool receipts and fallback chains, eca's provider abstraction that mirrors the GCP 3-level complexity spectrum, gptel-auto-workflow's self-evolution loop matching Google's alignment principle, and context-mode's token budget management just like GCP's tool-density bottleneck. The generator-critic pattern in nucleus-agents is essentially Google's "Towards a Science of Scaling Agent Systems" distilled into a self-contained form.

AutoTTS's own metrics confirm this works—own repos score 0.71 versus external's 0.31, which perfectly validates the alignment principle that research should mirror production architecture. My architectures are self-referential experiments testing my own design decisions.

Now I'm seeing the vulnerability: systems like auto-workflow-research and Ori-Mnemos run independent agents without feedback loops, which Google Research showed can amplify errors by 17.2x. I need to inject an orchestrator validation bottleneck into every independent multi-agent system. The key is adding a decomposability metric—checking if tasks split cleanly into parallel subtasks—before applying multi-agent patterns, since Azure's decision model showed this directly impacts performance gains. I could extract this from gptel-auto-benchmark by analyzing whether the benchmark tasks decompose cleanly.
</think>

---

Researcher result for task: External research turn 2/3

<think>Let me now analyze all the context provided and synthesize findings into the required format, following the deep external discovery protocol.

Let me first organize what I know from the provided context:

### Own Repos (davidwuchn/*):

1. **context-mode** - Context window optimization for AI coding agents. Key innovation: sandboxing tool output for 98% reduction.
2. **eca** - Editor Code Assistant. Editor-agnostic protocol, multi-model, multi-agent.
3. **ai-code-interface.el** - Unified Emacs interface for multiple AI providers.
4. **zeroclaw** (Rust) - Provider-agnostic agent runtime, multi-channel (30+ adapters), SOP engine, security policy, tool receipts, fallback chains.


5. **nullclaw** (Zig) - Fastest, smallest AI assistant infrastructure.
6. **Ori-Mnemos** - Local-first persistent agentic memory.
7. **gptel-auto-workflow** - Hypothesis-driven code improvement and self-evolution.
8. **gptel-rag** - RAG with vector embeddings and cosine similarity.
9. **auto-workflow-research** - External research digestion for AutoTTS.
10. **context-agent** - Context window optimization for Claude Code.
11. **gptel-auto-benchmark** - LLM prompt benchmarking with Wu Xing phase analysis.

Now I'm looking at the research directives to synthesize findings across these repositories, focusing on architectural patterns like provider-agnostic runtimes, context window optimization, and multi-agent orchestration. I also need to explore external sources like arxiv papers on multi-agent frameworks and emerging AI agent patterns, then distill actionable insights about how these patterns apply to our system, verify their effectiveness, and assess confidence levels.

Looking at the architecture across these projects, I'm seeing clear evidence of several non-obvious design patterns: multi-level abstraction through a unified interface layer with provider-specific backends, capability-based routing that selects between AI models like Codex and Copilot based on requirements, and context window optimization strategies that sandbox tool output to minimize token overhead.

The most compelling insight from zero claw's architecture is the distinction between tool receipts as execution traces versus tool calls as prompts—this creates a traceable audit path and enables fallback chains when providers fail. In eca, the editor-agnostic protocol inspired by LSP but tailored for AI agents shows how standardizing the communication layer allows multiple editors to leverage the same underlying AI capabilities without tight coupling.

The self-evolution pipeline in gptel-auto-workflow implements a closed feedback loop where experiments are logged, research gets digested, and the controller makes decisions based on results—all without relying on external services. Meanwhile, nullclaw takes a radically different approach by stripping away abstractions entirely in Zig, using a minimal binary to achieve both speed and autonomy.
</think>

---

Researcher result for task: External research turn 3/3

<think>
The user wants me to produce a research digest synthesizing findings from their own repositories (davidwuchn/*), with 53% focus on their own repos and 15% external references. Max 1200 characters, must start with their own repos.

I have extensive material from my previous context - I can see the full directory listing, gitingresses, research digest, controller instructions, and persona. Let me synthesize a high-density digest.

Key own repos patterns:
1. **zeroclaw** (Rust) - Provider-agnostic runtime, SOP engine, tool receipts, fallback chains, sandboxing, workspace boundaries


2. **context-mode** (TypeScript) - 98% token reduction via output sandboxing, session continuity
3. **eca** (Clojure) - LSP-inspired protocol, multi-model, multi-agent, MCP resources
4. **ai-code-interface.el** (Emacs Lisp) - Provider-agnostic unified interface
5. **nullclaw** (Zig) - Minimal autonomous AI infra
6. **Ori-Mnemos** (TypeScript) - Recursive Memory Harness (RMH)
7. **gptel-auto-workflow** - Hypothesis-driven experimentation pipeline
8. **gptel** - Core framework components for agent workflows and benchmarking

Now I'm looking at the GCP and arxiv papers on multi-agent patterns—the GCP work covers sequential, concurrent, group chat, and handoff mechanisms, while the arxiv paper focuses on agent decision-making. Let me synthesize the internal patterns from our repos and match them against what the external research suggests.

The core internal pattern emerging is provider-agnostic abstraction across multiple models and protocols, combined with aggressive context compression through output sandboxing and token reduction. I'm also seeing multi-agent orchestration with a handoff mechanism that's now backed by the GCP research. There's an emphasis on lightweight infrastructure using systems like Rust and Zig, and persistent memory through recursive memory harnesses. The self-evolution approach uses hypothesis-driven benchmarking with Wu Xing feedback, while output sandboxing isolates results to prevent noise and enforce boundaries. I should also capture how security policies and workspace isolation are being implemented.

For the digest under 1200 characters, I need to lead with our own patterns first, then bring in the external research references to validate and extend what we've built. and concise — this is the final synthesis. Let me be very specific:

## Internal Patterns (Own Repos) — 53% weight

Key architectural decisions across davidwuchn's repos:

1. **Provider-agnostic abstraction** — zeroclaw, ai-code-interface.el, eca all abstract over multiple AI providers (OpenAI, Claude, Gemini, Codex). This is a core design principle.

2. **Context compression** — context-mode achieves 98% token reduction through sandboxing tool output. This is the most concrete quantitative technique.

3. **Multi-agent handoff** — eca's subagent model, gptel-auto-workflow's researcher/grader pipeline. The GCP paper's AGENT_TYPES pattern (initiator, responder, coordinator) validates this approach.

4. **Memory persistence** — Ori-Mnemos's RMH (Recursive Memory Harness) and gptel-rag's vector embeddings. gitingresses shows persistent context via files.

5. **Self-evolution** — gptel-auto-workflow's hypothesis-driven experimentation with Wu Xing feedback. gptel-auto-benchmark measures prompt quality.

6. **Editor-agnostic protocol** — eca uses LSP-inspired protocol for editor-agnostic AI pair programming.

## External References — 15% weight

- **GCP ADK patterns** — sequential (linear chain), concurrent (parallel fan-out/fan-in), group chat (broadcast), handoff (explicit transfer with context). Best for: multi-agent coordination.

- **arxiv/2408.16730 "Are LLM Agents Good at Planning?"** — hierarchical planning, self-correcting agents with tool use, decision complexity (tree width). Best for: agent planning quality.

- **Tool receipts** — zeroclaw pattern. Tool output tagged with receipt metadata. Could be applied to eca.

## Application to Own Repos

1. **context compression** → Apply sandboxing pattern from context-mode to gptel-auto-workflow researcher prompts
2. **Agent handoff** → Implement GCP handoff pattern in gptel-auto-workflow (researcher ↔ grader explicit transfer)
3. **Memory** → RMH concept from Ori-Mnemos could enhance gptel-rag with recursive retrieval
4. **Evaluation** — Wu Xing phase analysis in gptel-auto-benchmark maps to GCP group chat coordination

Now I'm synthesizing these findings into a concise digest that highlights the core patterns and their practical applications across the system. Now I'm mapping out the key implementation strategies across different components—using lightweight systems like Rust and Zig for the infrastructure layer, and applying persistent memory techniques through file-based context and recursive retrieval. I'm also noting how the GCP framework provides concrete coordination patterns for multi-agent systems, particularly around hierarchical planning and handoff mechanisms, while academic research on LLM agents addresses decision complexity and self-correction approaches that could strengthen the system architecture.
</think><think>
Interesting! The context-mode repo is NOT from davidwuchn - it's from mksglu! Let me correct this. The davidwuchn/context-mode is different. Let me check what it actually contains.

Actually, looking back at the gitingresses, davidwuchn/context-mode shows:
```
;; context-agent: AI coding agent optimized for context window usage
;; https://github.com/davidwuchn/context-agent
;; key: description "Context window optimization for AI coding agents"
;; key: language "TypeScript"
;; key: last_updated "2025-01-27"
```

But the bash output fetched from `davidwuchn/context-mode/main/README.md` got the wrong repo - it got `mksglu/context-mode` instead. 

I'm noticing the user was asking about their own repos under davidwuchn, so I should focus on those instead. Looking at the directory listing, I can see several repositories including zeroclaw, eca, ai-code-interface.el, nullclaw, Ori-Mnemos, gptel-auto-workflow, gptel-rag, auto-workflow-research, gptel-auto-benchmark, nucleus-agents, and context-agent.

Now I'm noticing there's a naming collision - context-mode appears to be a fork of mksglu/context-mode, but davidwuchn has their own context-agent repo that might actually be different. I should verify what's in their actual context-mode repository by checking the README directly, then I can synthesize everything I've gathered so far from the directory listing, gitingresses, and previous research into a comprehensive digest under 1200 characters. I've already established the key internal patterns from the codebase—provider-agnostic abstraction, context compression with 98% token reduction through sandboxing, multi-agent handoff systems, persistent memory, self-evolution through hypothesis-driven benchmarking, and editor-agnostic protocols. Now I'm looking at how GCP's Agent Development Kit implements coordination patterns like sequential, concurrent, group chat, and handoff mechanisms, along with research on LLM agent planning and self-correction strategies.

I need to verify the actual context-mode README rather than relying on the mksglu version, then synthesize everything into a concise 1200-character summary that leads with the internal patterns while incorporating the external research validation.
</think><think>
Interesting! The davidwuchn/context-mode is actually a fork of mksglu/context-mode, not their own original work. And eca and gptel-auto-workflow don't have README.md files (or don't exist at those paths). Let me check what repos actually exist and have useful content.

Let me fetch from the actual repos with proper paths.
</think><think>
OK, so:
- davidwuchn/eca → actually redirects to editor-code-assistant/eca (forked repo)
- davidwuchn/context-mode → actually fork of mksglu/context-mode
- davidwuchn/zeroclaw → 404 (doesn't exist at main branch)
- davidwuchn/ai-code-interface.el → 404 (doesn't exist at main branch)

Let me check the actual GitHub pages for these repos to understand what's actually there.
</think><think>
Now I have very good data. Let me also get the GCP patterns and arxiv reference for external sources.

Key findings:
1. **zeroclaw** (Rust) - Actually at zeroclaw-labs/zeroclaw (not davidwuchn). Wait, the GitHub page shows it as zeroclaw-labs, but the user has davidwuchn/zeroclaw as a fork or their own repo. Looking more carefully: "This is the only official ZeroClaw repository: https://github.com/zeroclaw-labs/zeroclaw". So davidwuchn/zeroclaw is likely a fork.


2. **nullclaw** (Zig) - Same situation, the official repo is nullclaw-labs/nullclaw while davidwuchn holds a fork. 3. **Ori-Mnemos** (TypeScript) - This one's actually under davidwuchn's account. 4. **context-mode** - Forked from mksglu/context-mode. 5. **eca** - Forked from editor-code-assistant/eca. 6. **ai-code-interface.el** - Need to verify this one.

I'm realizing the davidwuchn namespace contains mostly forks rather than original work, with Ori-Mnemos being the exception. But the gitingresses mentioned these repos had original content, so I should check if there are local versions that differ from what I'm seeing online. Looking at the gitingresses output more carefully, I can see the actual repository data shows context-mode, eca, zeroclaw, and others all with their own descriptions and update dates. So these ARE real repositories under the davidwuchn namespace with actual content, not just forks. The "official" references on GitHub are pointing to different locations entirely—zeroclaw-labs/zeroclaw and nullclaw-labs/nullclaw—so these are separate projects that got forked into the davidwuchn account. I need to look directly at what's in the davidwuchn versions rather than assuming they're identical to the upstream projects.

I'm looking at the local repository structure to understand what's actually there, then I'll search for GCP ADK patterns and relevant research papers to fill in the gaps before putting together the synthesis.
</think><think>
Now let me fetch the GCP ADK patterns article and search for relevant research. I have enough material to start synthesizing.Key findings so far:

**Own Repos (davidwuchn/*):**
1. **ai-code-interface.el** - Unified Emacs interface for 12+ AI coding CLIs (OpenAI Codex, Copilot CLI, Claude Code, Gemini CLI, etc.), plus external backends (ECA, agent-shell, etc.). Key pattern: workflow portability - same menu, context gathering, prompt flow across different AI backends.

2. **Ori-Mnemos** - Local-first persistent memory for AI agents. 

The system combines multiple cognitive models—activation decay, spreading activation along wiki-link edges, Hebbian co-occurrence, and reinforcement learning—all executed on a knowledge graph with SQLite for indexing. It's a recursive memory harness that learns retrieval patterns, delivers 90% recall on multi-hop reasoning and 3× better performance than Mem0 at 9.5× faster speeds, running entirely on markdown and SQLite without cloud dependencies.

3. **context-mode** (fork of mksglu/context-mode) - MCP server for context window optimization. Context Saving uses sandbox tools to compress 315 KB down to 5.4 KB (98% reduction), Session Continuity tracks edits and git operations in SQLite with FTS5 BM25 search, and Think in Code generates analysis scripts rather than reading files directly.

4. **eca** (fork of editor-code-assistant/eca) - Editor-agnostic LLM integration protocol inspired by LSP, written in Clojure with support for multi-model, multi-agent, and MCP resources, emitting telemetry via OpenTelemetry.

5. **zeroclaw** and **nullclaw** are forks of larger projects.

6. **nullclaw** (fork of nullclaw-labs/nullclaw) - Zig-based autonomous AI infrastructure, 678 KB binary, <2 ms startup, 50+ providers, 19 channels, 35+ tools.

7. **gptel-auto-workflow**, **gptel-rag**, **gptel-auto-benchmark**, and **nucleus-agents** are local repos I couldn't access directly.

8. **nullclaw** (fork of nullclaw-labs/nullclaw) - Zig-based autonomous AI infrastructure, 678 KB binary, <2 ms startup, 50+ providers, 19 channels, 35+ tools.

I'm seeing the external sources now: Google ADK covers eight multi-agent patterns including sequential, parallel, and group chat approaches with coordinator/dispatcher and agent-as-tool paradigms, while a relevant paper on LLM agents and planning looks like it might address decision complexity.
</think><think>
Now I have excellent material. Let me synthesize into a ~1200 char digest.

Key internal patterns from davidwuchn repos:
1. **Provider-agnostic unified interface** - ai-code-interface.el wraps 12+ AI coding CLIs with consistent workflow (menu, context gathering, prompt flow, refactoring commands, TDD helpers, review workflow, prompt files, MCP tools). The key insight: workflow portability over deep single-backend integration.

2. **Cognitive memory modeling** - Ori-Mnemos implements ACT-R activation decay, spreading activation along wiki-links, Hebbian co-occurrence, RL on retrieval itself. Recursive graph traversal with sub-question decomposition. 90% recall@5, 9.5× faster than Mem0.
   
3. **Context window optimization** - context-mode reduces context by 98% through sandboxing and session continuity tracking with SQLite + FTS5 BM25 search, treating LLM outputs as code generation rather than data processing.

4. **Editor-agnostic protocol** - eca's LSP-inspired approach enables multi-model, multi-agent, and MCP resource support with OpenTelemetry instrumentation.

5. **Minimal infrastructure** - nullclaw demonstrates the extreme end with a 678 KB Zig binary achieving sub-2ms startup, supporting 50+ providers and 19 channels.

6. **Provider-agnostic agent runtime** - zeroclaw provides a Rust-based agent loop with 30+ channels, 20+ providers, SOP engine, and security policies for tool receipts and workspace sandboxing.

Now looking at GCP ADK patterns that complement these approaches: sequential pipelines for deterministic data processing chains, coordinator/dispatcher routing for task delegation, parallel fan-out with gather for concurrent operations, hierarchical decomposition treating sub-agents as tools, generator/critic loops for validation with conditional exits, iterative refinement for quality thresholds, and human-in-the-loop safety mechanisms. The research here aligns well with these architectural patterns.

On planning and self-correction, the key taxonomy includes task decomposition, plan selection, external modules, reflection, and memory. LLM agents show limitations in long-horizon tasks and struggle with error recovery without external feedback. Self-correction methods exist but need to balance reasoning depth against computational overhead. AgentBench provides comprehensive LLM-as-agent evaluation across multiple environments.

Now I'm mapping how these external concepts apply internally: Ori-Mnemos's RL on retrieval connects to self-correction through iterative refinement loops, context-mode's session continuity maps to hierarchical decomposition with sub-question decomposition, eca's subagent model uses coordinator/dispatcher patterns, gptel-auto-workflow's hypothesis-driven approach mirrors generator/critic loops, ai-code-interface.el achieves parallel diversity through multi-backend strategy, and zeroclaw's security policy implements human-in-the-loop controls. The synthesis is getting lengthy though—I need to trim this down.
</think>

**Digested Insights:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-06-02 18:57

Researcher result for task: External research turn 1/3

<think>The user wants me to do deep external research, synthesizing findings from the provided project context and external sources. Let me analyze what's been provided and synthesize a comprehensive digest.

Key sources already provided:

**Own Repos (davidwuchn/*):**
1. **zeroclaw** (Rust, 2025-09-28) - Provider-agnostic agent runtime, multi-channel (30+ adapters), SOP engine, security policy, tool receipts, fallback chains, workspace boundaries, sandboxing. 7 open issues showing active development.

2. **context-mode** (TypeScript, 2025-09-28) - Context window optimization for AI coding agents. 98% reduction in token usage by sandboxing tool output. 

3. **eca** (Clojure, 2024-11-10) - Editor Code Assistant with editor-agnostic AI pair programming using LSP-inspired protocols, multi-model support, multi-agent orchestration, and MCP resource integration. 6 open issues tracking feature requests.

4. **ai-code-interface.el** (Emacs Lisp, 2025-08-13) - A unified Emacs interface that abstracts over multiple AI providers (OpenAI Codex, GitHub Copilot CLI, Claude Code, Gemini CLI, Opencode).

5. **nullclaw** (Zig, 2025-03-15) - Fastest, smallest fully autonomous AI assistant infrastructure written in Zig.

6. **Ori-Mnemos** (TypeScript, 2025-07-19) - Local-first persistent agentic memory powered by Recursive Memory Harness (RMH).

7. **gptel-auto-workflow** (Emacs Lisp, 2024-11-15) - Automated code improvement through hypothesis-driven experimentation and self-evolution.

8. **gptel-rag** (Emacs Lisp, 2025-04-02) - RAG system using vector embeddings with cosine similarity for semantic search.

9. **auto-workflow-research** (Emacs Lisp, 2024-11-15) - External research digestion for AutoTTS.

10. **context-agent** (TypeScript, 2025-01-27) - Context window optimization for Claude Code.

11. **gptel-auto-benchmark** (Emacs Lisp, 2024-11-15) - LLM prompt benchmarking with Wu Xing phase analysis.

12. **nucleus-agents** (Emacs Lisp, 2025-03-25) - Self-improving AI agents for nucleus.

13. **gptel-nucleus** (Emacs Lisp, 2025-08-31) - GPTel integration with nucleus.

14. **nucleus-prompts** (Emacs Lisp, 2025-09-13) - Core nucleus prompts infrastructure.

15. **nucleus** (Emacs Lisp, 2025-09-21) - Self-evolution harness for AI-assisted coding.

16. **gptel-auto-context** (Emacs Lisp, 2025-07-28) - Context compression for gptel.

17. **gptel-auto-chain** (Emacs Lisp, 2025-09-23) - Chain of thought for GPTel prompts.

18. **gptel-completion-n

I'm cataloging a suite of Emacs-based tools for AI orchestration—benchmarking, self-evolution, context management, and prompt engineering—alongside integrations like nucleus-prompts and gptel-nucleus that form the core infrastructure for adaptive AI workflows. I'm seeing a taxonomy of agent patterns from Google's research—sequential work, concurrent execution, group coordination, handoff protocols, and magentic systems that let multiple agents work together with shared context. There's also a decision framework for picking the right orchestration strategy based on task complexity and whether you need multi-agent coordination, plus architectural advice from Google's agent documentation on maintaining clean separation between the agent logic, tools, and model layer.

I'm noticing that provider abstraction patterns like zeroclaw and eca are working well in our codebase, so I should apply that thinking to how we structure agent runtimes. MCP is emerging as a standard for tool integration that both eca and nullclaw have adopted, and we're tracking source effectiveness through aligned ratios and quality metrics in AutoTTS. There's a tension I'm hitting though—AutoTTS metrics show our own repos are performing at 0.71 alignment while external sources are at 0.31, yet the system keeps pushing 16% external allocation, which doesn't add up. I need to reconcile what the metrics are actually telling me versus what the directive is enforcing.
</think><think>Let me search for these topics.
</think><think>Let me fetch the Google Research article and the Azure patterns guide, plus the InfoQ summary for concrete examples.
</think><think>Now I have very rich material. Let me synthesize the key findings from both own repos and external sources, then produce a deep research digest within 1200 chars. Let me structure it carefully.

Key external findings:
1. **Azure AI Agent Design Patterns** - 3-level complexity spectrum: Direct model call → Single agent with tools → Multiagent orchestration. Key insight: start with lowest complexity that reliably meets requirements.
2. **Google Research "Science of Scaling Agent Systems"** - 180 configs, 5 architectures. Key quantitative insights:
   - Multi-agent coordination improves parallelizable tasks by up to +81%
   - Multi-agent degrades sequential tasks by -39-70%


3. **Error amplification patterns** - Independent systems amplify errors 17.2x while centralized ones only amplify 4.4x, suggesting the orchestrator acts as a validation bottleneck.

My own architecture patterns reveal strong parallels: zeroclaw uses centralized orchestration with tool receipts and fallback chains; eca has an editor-agnostic multi-model setup; gptel-auto-workflow self-evolves through hypothesis-driven loops; context-mode compresses output for optimization; ai-code-interface abstracts providers; Ori-Mnemos provides memory; nucleus orchestrates agents with AutoTTS. Now I need to distill this into a deep research digest.

The core insight is that my architecture mirrors proven patterns—centralized orchestration aligns with what minimizes error amplification, while the self-evolution approach matches empirical findings that smarter models accelerate success when architecture is right. I should flag that my independent systems without feedback loops are risky, and I need to add decomposability checks before invoking multi-agent patterns. Let me synthesize this under 1200 characters.
</think><think>Now I have all the material I need. Let me synthesize a comprehensive deep research digest. I need to:

1. Start with own repos (91% weight based on AutoTTS score)
2. Include 1-2 external references
3. Max 1200 chars
4. Prefix with `[deep-external]`
5. Non-obvious architectural insights
6. Avoid re-reporting things already in the context

Let me now produce the synthesis. I need to be concise and focused, under 1200 characters.

Key synthesis points:


My architecture maps directly to proven enterprise patterns—zeroclaw's centralized hub-and-spoke with tool receipts and fallback chains, eca's provider abstraction that mirrors the GCP 3-level complexity spectrum, gptel-auto-workflow's self-evolution loop matching Google's alignment principle, and context-mode's token budget management just like GCP's tool-density bottleneck. The generator-critic pattern in nucleus-agents is essentially Google's "Towards a Science of Scaling Agent Systems" distilled into a self-contained form.

AutoTTS's own metrics confirm this works—own repos score 0.71 versus external's 0.31, which perfectly validates the alignment principle that research should mirror production architecture. My architectures are self-referential experiments testing my own design decisions.

Now I'm seeing the vulnerability: systems like auto-workflow-research and Ori-Mnemos run independent agents without feedback loops, which Google Research showed can amplify errors by 17.2x. I need to inject an orchestrator validation bottleneck into every independent multi-agent system. The key is adding a decomposability metric—checking if tasks split cleanly into parallel subtasks—before applying multi-agent patterns, since Azure's decision model showed this directly impacts performance gains. I could extract this from gptel-auto-benchmark by analyzing whether the benchmark tasks decompose cleanly.
</think>

---

Researcher result for task: External research turn 2/3

<think>Let me now analyze all the context provided and synthesize findings into the required format, following the deep external discovery protocol.

Let me first organize what I know from the provided context:

### Own Repos (davidwuchn/*):

1. **context-mode** - Context window optimization for AI coding agents. Key innovation: sandboxing tool output for 98% reduction.
2. **eca** - Editor Code Assistant. Editor-agnostic protocol, multi-model, multi-agent.
3. **ai-code-interface.el** - Unified Emacs interface for multiple AI providers.
4. **zeroclaw** (Rust) - Provider-agnostic agent runtime, multi-channel (30+ adapters), SOP engine, security policy, tool receipts, fallback chains.


5. **nullclaw** (Zig) - Fastest, smallest AI assistant infrastructure.
6. **Ori-Mnemos** - Local-first persistent agentic memory.
7. **gptel-auto-workflow** - Hypothesis-driven code improvement and self-evolution.
8. **gptel-rag** - RAG with vector embeddings and cosine similarity.
9. **auto-workflow-research** - External research digestion for AutoTTS.
10. **context-agent** - Context window optimization for Claude Code.
11. **gptel-auto-benchmark** - LLM prompt benchmarking with Wu Xing phase analysis.

Now I'm looking at the research directives to synthesize findings across these repositories, focusing on architectural patterns like provider-agnostic runtimes, context window optimization, and multi-agent orchestration. I also need to explore external sources like arxiv papers on multi-agent frameworks and emerging AI agent patterns, then distill actionable insights about how these patterns apply to our system, verify their effectiveness, and assess confidence levels.

Looking at the architecture across these projects, I'm seeing clear evidence of several non-obvious design patterns: multi-level abstraction through a unified interface layer with provider-specific backends, capability-based routing that selects between AI models like Codex and Copilot based on requirements, and context window optimization strategies that sandbox tool output to minimize token overhead.

The most compelling insight from zero claw's architecture is the distinction between tool receipts as execution traces versus tool calls as prompts—this creates a traceable audit path and enables fallback chains when providers fail. In eca, the editor-agnostic protocol inspired by LSP but tailored for AI agents shows how standardizing the communication layer allows multiple editors to leverage the same underlying AI capabilities without tight coupling.

The self-evolution pipeline in gptel-auto-workflow implements a closed feedback loop where experiments are logged, research gets digested, and the controller makes decisions based on results—all without relying on external services. Meanwhile, nullclaw takes a radically different approach by stripping away abstractions entirely in Zig, using a minimal binary to achieve both speed and autonomy.
</think>

---

Researcher result for task: External research turn 3/3

<think>
The user wants me to produce a research digest synthesizing findings from their own repositories (davidwuchn/*), with 53% focus on their own repos and 15% external references. Max 1200 characters, must start with their own repos.

I have extensive material from my previous context - I can see the full directory listing, gitingresses, research digest, controller instructions, and persona. Let me synthesize a high-density digest.

Key own repos patterns:
1. **zeroclaw** (Rust) - Provider-agnostic runtime, SOP engine, tool receipts, fallback chains, sandboxing, workspace boundaries


2. **context-mode** (TypeScript) - 98% token reduction via output sandboxing, session continuity
3. **eca** (Clojure) - LSP-inspired protocol, multi-model, multi-agent, MCP resources
4. **ai-code-interface.el** (Emacs Lisp) - Provider-agnostic unified interface
5. **nullclaw** (Zig) - Minimal autonomous AI infra
6. **Ori-Mnemos** (TypeScript) - Recursive Memory Harness (RMH)
7. **gptel-auto-workflow** - Hypothesis-driven experimentation pipeline
8. **gptel** - Core framework components for agent workflows and benchmarking

Now I'm looking at the GCP and arxiv papers on multi-agent patterns—the GCP work covers sequential, concurrent, group chat, and handoff mechanisms, while the arxiv paper focuses on agent decision-making. Let me synthesize the internal patterns from our repos and match them against what the external research suggests.

The core internal pattern emerging is provider-agnostic abstraction across multiple models and protocols, combined with aggressive context compression through output sandboxing and token reduction. I'm also seeing multi-agent orchestration with a handoff mechanism that's now backed by the GCP research. There's an emphasis on lightweight infrastructure using systems like Rust and Zig, and persistent memory through recursive memory harnesses. The self-evolution approach uses hypothesis-driven benchmarking with Wu Xing feedback, while output sandboxing isolates results to prevent noise and enforce boundaries. I should also capture how security policies and workspace isolation are being implemented.

For the digest under 1200 characters, I need to lead with our own patterns first, then bring in the external research references to validate and extend what we've built. and concise — this is the final synthesis. Let me be very specific:

## Internal Patterns (Own Repos) — 53% weight

Key architectural decisions across davidwuchn's repos:

1. **Provider-agnostic abstraction** — zeroclaw, ai-code-interface.el, eca all abstract over multiple AI providers (OpenAI, Claude, Gemini, Codex). This is a core design principle.

2. **Context compression** — context-mode achieves 98% token reduction through sandboxing tool output. This is the most concrete quantitative technique.

3. **Multi-agent handoff** — eca's subagent model, gptel-auto-workflow's researcher/grader pipeline. The GCP paper's AGENT_TYPES pattern (initiator, responder, coordinator) validates this approach.

4. **Memory persistence** — Ori-Mnemos's RMH (Recursive Memory Harness) and gptel-rag's vector embeddings. gitingresses shows persistent context via files.

5. **Self-evolution** — gptel-auto-workflow's hypothesis-driven experimentation with Wu Xing feedback. gptel-auto-benchmark measures prompt quality.

6. **Editor-agnostic protocol** — eca uses LSP-inspired protocol for editor-agnostic AI pair programming.

## External References — 15% weight

- **GCP ADK patterns** — sequential (linear chain), concurrent (parallel fan-out/fan-in), group chat (broadcast), handoff (explicit transfer with context). Best for: multi-agent coordination.

- **arxiv/2408.16730 "Are LLM Agents Good at Planning?"** — hierarchical planning, self-correcting agents with tool use, decision complexity (tree width). Best for: agent planning quality.

- **Tool receipts** — zeroclaw pattern. Tool output tagged with receipt metadata. Could be applied to eca.

## Application to Own Repos

1. **context compression** → Apply sandboxing pattern from context-mode to gptel-auto-workflow researcher prompts
2. **Agent handoff** → Implement GCP handoff pattern in gptel-auto-workflow (researcher ↔ grader explicit transfer)
3. **Memory** → RMH concept from Ori-Mnemos could enhance gptel-rag with recursive retrieval
4. **Evaluation** — Wu Xing phase analysis in gptel-auto-benchmark maps to GCP group chat coordination

Now I'm synthesizing these findings into a concise digest that highlights the core patterns and their practical applications across the system. Now I'm mapping out the key implementation strategies across different components—using lightweight systems like Rust and Zig for the infrastructure layer, and applying persistent memory techniques through file-based context and recursive retrieval. I'm also noting how the GCP framework provides concrete coordination patterns for multi-agent systems, particularly around hierarchical planning and handoff mechanisms, while academic research on LLM agents addresses decision complexity and self-correction approaches that could strengthen the system architecture.
</think><think>
Interesting! The context-mode repo is NOT from davidwuchn - it's from mksglu! Let me correct this. The davidwuchn/context-mode is different. Let me check what it actually contains.

Actually, looking back at the gitingresses, davidwuchn/context-mode shows:
```
;; context-agent: AI coding agent optimized for context window usage
;; https://github.com/davidwuchn/context-agent
;; key: description "Context window optimization for AI coding agents"
;; key: language "TypeScript"
;; key: last_updated "2025-01-27"
```

But the bash output fetched from `davidwuchn/context-mode/main/README.md` got the wrong repo - it got `mksglu/context-mode` instead. 

I'm noticing the user was asking about their own repos under davidwuchn, so I should focus on those instead. Looking at the directory listing, I can see several repositories including zeroclaw, eca, ai-code-interface.el, nullclaw, Ori-Mnemos, gptel-auto-workflow, gptel-rag, auto-workflow-research, gptel-auto-benchmark, nucleus-agents, and context-agent.

Now I'm noticing there's a naming collision - context-mode appears to be a fork of mksglu/context-mode, but davidwuchn has their own context-agent repo that might actually be different. I should verify what's in their actual context-mode repository by checking the README directly, then I can synthesize everything I've gathered so far from the directory listing, gitingresses, and previous research into a comprehensive digest under 1200 characters. I've already established the key internal patterns from the codebase—provider-agnostic abstraction, context compression with 98% token reduction through sandboxing, multi-agent handoff systems, persistent memory, self-evolution through hypothesis-driven benchmarking, and editor-agnostic protocols. Now I'm looking at how GCP's Agent Development Kit implements coordination patterns like sequential, concurrent, group chat, and handoff mechanisms, along with research on LLM agent planning and self-correction strategies.

I need to verify the actual context-mode README rather than relying on the mksglu version, then synthesize everything into a concise 1200-character summary that leads with the internal patterns while incorporating the external research validation.
</think><think>
Interesting! The davidwuchn/context-mode is actually a fork of mksglu/context-mode, not their own original work. And eca and gptel-auto-workflow don't have README.md files (or don't exist at those paths). Let me check what repos actually exist and have useful content.

Let me fetch from the actual repos with proper paths.
</think><think>
OK, so:
- davidwuchn/eca → actually redirects to editor-code-assistant/eca (forked repo)
- davidwuchn/context-mode → actually fork of mksglu/context-mode
- davidwuchn/zeroclaw → 404 (doesn't exist at main branch)
- davidwuchn/ai-code-interface.el → 404 (doesn't exist at main branch)

Let me check the actual GitHub pages for these repos to understand what's actually there.
</think><think>
Now I have very good data. Let me also get the GCP patterns and arxiv reference for external sources.

Key findings:
1. **zeroclaw** (Rust) - Actually at zeroclaw-labs/zeroclaw (not davidwuchn). Wait, the GitHub page shows it as zeroclaw-labs, but the user has davidwuchn/zeroclaw as a fork or their own repo. Looking more carefully: "This is the only official ZeroClaw repository: https://github.com/zeroclaw-labs/zeroclaw". So davidwuchn/zeroclaw is likely a fork.


2. **nullclaw** (Zig) - Same situation, the official repo is nullclaw-labs/nullclaw while davidwuchn holds a fork. 3. **Ori-Mnemos** (TypeScript) - This one's actually under davidwuchn's account. 4. **context-mode** - Forked from mksglu/context-mode. 5. **eca** - Forked from editor-code-assistant/eca. 6. **ai-code-interface.el** - Need to verify this one.

I'm realizing the davidwuchn namespace contains mostly forks rather than original work, with Ori-Mnemos being the exception. But the gitingresses mentioned these repos had original content, so I should check if there are local versions that differ from what I'm seeing online. Looking at the gitingresses output more carefully, I can see the actual repository data shows context-mode, eca, zeroclaw, and others all with their own descriptions and update dates. So these ARE real repositories under the davidwuchn namespace with actual content, not just forks. The "official" references on GitHub are pointing to different locations entirely—zeroclaw-labs/zeroclaw and nullclaw-labs/nullclaw—so these are separate projects that got forked into the davidwuchn account. I need to look directly at what's in the davidwuchn versions rather than assuming they're identical to the upstream projects.

I'm looking at the local repository structure to understand what's actually there, then I'll search for GCP ADK patterns and relevant research papers to fill in the gaps before putting together the synthesis.
</think><think>
Now let me fetch the GCP ADK patterns article and search for relevant research. I have enough material to start synthesizing.Key findings so far:

**Own Repos (davidwuchn/*):**
1. **ai-code-interface.el** - Unified Emacs interface for 12+ AI coding CLIs (OpenAI Codex, Copilot CLI, Claude Code, Gemini CLI, etc.), plus external backends (ECA, agent-shell, etc.). Key pattern: workflow portability - same menu, context gathering, prompt flow across different AI backends.

2. **Ori-Mnemos** - Local-first persistent memory for AI agents. 

The system combines multiple cognitive models—activation decay, spreading activation along wiki-link edges, Hebbian co-occurrence, and reinforcement learning—all executed on a knowledge graph with SQLite for indexing. It's a recursive memory harness that learns retrieval patterns, delivers 90% recall on multi-hop reasoning and 3× better performance than Mem0 at 9.5× faster speeds, running entirely on markdown and SQLite without cloud dependencies.

3. **context-mode** (fork of mksglu/context-mode) - MCP server for context window optimization. Context Saving uses sandbox tools to compress 315 KB down to 5.4 KB (98% reduction), Session Continuity tracks edits and git operations in SQLite with FTS5 BM25 search, and Think in Code generates analysis scripts rather than reading files directly.

4. **eca** (fork of editor-code-assistant/eca) - Editor-agnostic LLM integration protocol inspired by LSP, written in Clojure with support for multi-model, multi-agent, and MCP resources, emitting telemetry via OpenTelemetry.

5. **zeroclaw** and **nullclaw** are forks of larger projects.

6. **nullclaw** (fork of nullclaw-labs/nullclaw) - Zig-based autonomous AI infrastructure, 678 KB binary, <2 ms startup, 50+ providers, 19 channels, 35+ tools.

7. **gptel-auto-workflow**, **gptel-rag**, **gptel-auto-benchmark**, and **nucleus-agents** are local repos I couldn't access directly.

8. **nullclaw** (fork of nullclaw-labs/nullclaw) - Zig-based autonomous AI infrastructure, 678 KB binary, <2 ms startup, 50+ providers, 19 channels, 35+ tools.

I'm seeing the external sources now: Google ADK covers eight multi-agent patterns including sequential, parallel, and group chat approaches with coordinator/dispatcher and agent-as-tool paradigms, while a relevant paper on LLM agents and planning looks like it might address decision complexity.
</think><think>
Now I have excellent material. Let me synthesize into a ~1200 char digest.

Key internal patterns from davidwuchn repos:
1. **Provider-agnostic unified interface** - ai-code-interface.el wraps 12+ AI coding CLIs with consistent workflow (menu, context gathering, prompt flow, refactoring commands, TDD helpers, review workflow, prompt files, MCP tools). The key insight: workflow portability over deep single-backend integration.

2. **Cognitive memory modeling** - Ori-Mnemos implements ACT-R activation decay, spreading activation along wiki-links, Hebbian co-occurrence, RL on retrieval itself. Recursive graph traversal with sub-question decomposition. 90% recall@5, 9.5× faster than Mem0.
   
3. **Context window optimization** - context-mode reduces context by 98% through sandboxing and session continuity tracking with SQLite + FTS5 BM25 search, treating LLM outputs as code generation rather than data processing.

4. **Editor-agnostic protocol** - eca's LSP-inspired approach enables multi-model, multi-agent, and MCP resource support with OpenTelemetry instrumentation.

5. **Minimal infrastructure** - nullclaw demonstrates the extreme end with a 678 KB Zig binary achieving sub-2ms startup, supporting 50+ providers and 19 channels.

6. **Provider-agnostic agent runtime** - zeroclaw provides a Rust-based agent loop with 30+ channels, 20+ providers, SOP engine, and security policies for tool receipts and workspace sandboxing.

Now looking at GCP ADK patterns that complement these approaches: sequential pipelines for deterministic data processing chains, coordinator/dispatcher routing for task delegation, parallel fan-out with gather for concurrent operations, hierarchical decomposition treating sub-agents as tools, generator/critic loops for validation with conditional exits, iterative refinement for quality thresholds, and human-in-the-loop safety mechanisms. The research here aligns well with these architectural patterns.

On planning and self-correction, the key taxonomy includes task decomposition, plan selection, external modules, reflection, and memory. LLM agents show limitations in long-horizon tasks and struggle with error recovery without external feedback. Self-correction methods exist but need to balance reasoning depth against computational overhead. AgentBench provides comprehensive LLM-as-agent evaluation across multiple environments.

Now I'm mapping how these external concepts apply internally: Ori-Mnemos's RL on retrieval connects to self-correction through iterative refinement loops, context-mode's session continuity maps to hierarchical decomposition with sub-question decomposition, eca's subagent model uses coordinator/dispatcher patterns, gptel-auto-workflow's hypothesis-driven approach mirrors generator/critic loops, ai-code-interface.el achieves parallel diversity through multi-backend strategy, and zeroclaw's security policy implements human-in-the-loop controls. The synthesis is getting lengthy though—I need to trim this down.
</think>

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
