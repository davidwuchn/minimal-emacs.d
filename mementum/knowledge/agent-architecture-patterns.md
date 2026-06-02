---
title: "AI Agent Architecture Patterns"
category: research
tags: [agent-architecture, workflow, memory, error-recovery, orchestration, context-management, self-evolution]
sources:
  - id: own-repos
    weight: 0.53
    repos: [zeroclaw, nullclaw, eca, context-mode, ai-code-interface.el, genesis-agent, gbrain, nucleus, mementum, efrit, gastown, psi]
  - id: external
    weight: 0.15
    papers: [arXiv:2601.13671, arXiv:2510.00615, arXiv:2604.04869, arXiv:2603.07670, arXiv:2508.00271]
    blogs: [Azure Architecture Guide, callsphere.ai, sukany.cz, dipankar.cc, aiagentsblog.com]
created: 2026-05-22
updated: 2026-05-31
confidence: 0.60
outcome: 13/105 kept (12%)
---

# AI Agent Architecture Patterns

Compiled from 14 research turns across davidwuchn/* own repos and external sources (arXiv papers, Azure architecture guides, blog posts). This document serves as the canonical reference for AI agent design patterns applicable to Emacs Lisp AI systems. Confidence is 0.60 based on 12% pattern retention — many patterns are speculative and need experimental validation in the auto-workflow system.

**Budget**: 53% own repos, 15% external references, 32% synthesis.

**Research trajectory**: Started with deep own-repo analysis (davidwuchn/*) at 87% weight, shifted to external sources after internal patterns exhausted. Final synthesis phase blends both.

---

## Chapter 1: Own Repos — Infrastructure

### 1. Zeroclaw — Provider-Agnostic Agent Runtime

**Language:** Rust
**Repo:** https://github.com/davidwuchn/zeroclaw

The most comprehensive agent runtime. Covers the full loop from provider abstraction to sandboxing.

#### Patterns Extracted

- **Provider-agnostic runtime**: Pluggable LLM backends via vtable interfaces. Same code base swaps providers. 50+ providers documented.
- **Multi-channel architecture**: 30+ adapters (Discord, Telegram, Matrix, Slack, Email, SMS, etc.). Separates transport from agent logic.
- **SOP (Standard Operating Procedures) engine**: Event-triggered workflows. Statecharts compose by concatenation.
- **Fallback chains**: Provider A → Provider B → Provider C with automatic failover. Circuit breaker per provider.
- **Workspace boundaries**: Sandboxing at OS level (Landlock on Linux, Bubblewrap, Seatbelt on macOS). Tool receipts for cryptographic verification.
- **Tool receipts**: Every tool execution generates structured metadata: `(input-hash output-hash timestamp duration tool-name)`.
- **Security policy**: Shell commands have allowed/forbidden pattern matching. Prevents injection attacks.
- **ACP protocol**: IDE integration via JSON-RPC over stdio. TOML configuration files.

#### Verification
- Confirmed via README inspection
- Active development (recent commits)
- Production-vetted in multi-channel deployment

#### Apply-to-Us
Adopt provider-agnostic architecture from zeroclaw. Our gptel already has multi-backend support but lacks explicit fallback chains. Implement `gptel--fallback-chain` that tries providers in priority order with circuit-breaker state per backend.

---

### 2. Nullclaw — Minimal Binary Design

**Language:** Zig
**Repo:** https://github.com/davidwuchn/nullclaw

"Fastest, smallest, fully autonomous AI assistant infrastructure." Targets embedded/resource-constrained environments.

#### Patterns Extracted

- **Minimal footprint**: 678 KB static binary, ~1 MB RAM, <2ms startup. No runtime, no GC.
- **vtable interfaces**: Pluggable interfaces for providers, channels, tools, memory engines, peripherals. Compile-time dispatch.
- **Multi-layer sandbox**: landlock → firejail → bubblewrap → docker hierarchy. Defense in depth.
- **Workspace scoping**: Tool access limited to current project directory.
- **Encrypted secrets**: API keys never in plaintext; retrieved at runtime.
- **Feature-complete**: 50+ providers, 19 channels, 35+ tools, 10 memory engines.
- **MCP support**: Native Model Context Protocol integration.
- **Subagent support**: Parallel agent execution within single binary.

#### Verification
- Binary size and RAM figures confirmed via README
- Active development (recent commits)

#### Apply-to-Us
Target leaner elisp modules. Our auto-workflow modules could benefit from minimal dependencies. Use `byte-compile` aggressively. The multi-layer sandbox concept maps to Emacs: `let-bind` → `condition-case` → `with-local-quit` → dedicated subprocess.

---

### 3. Mementum — Git-Based Memory Protocol

**Language:** Bash/Emacs Lisp
**Repo:** https://github.com/davidwuchn/mementum

Git-native memory with session continuity across AI sessions.

#### Patterns Extracted

- **Feed-forward protocol**: Knowledge persists via git. Future sessions warm-start from accumulated memory.
- **Three storage types**:
  - `state.md` — working memory / session bootloader
  - `memories/` — raw observations, <200 words each, symbol-prefixed (💡 insight, 🔄 shift, 🎯 decision, 🌀 meta)
  - `knowledge/` — synthesized maps with YAML frontmatter (created, tags, source)
- **Seven operations**: create, create-knowledge, update, delete, search, read, synthesize.
- **Fibonacci recall depth**: `git log -n φ^k` where k = concept complexity. Default depth 2, progression: 2→3→5→8→13→21.
- **Synthesis trigger**: ≥3 memories on same topic OR stale memory OR crystallized concept → metabolize flow: detect → gather → draft → create-knowledge → update stale → verify.
- **Human governance**: AI proposes → human approves → AI commits.
- **Token budget**: ≤200 tokens per memory entry.
- **λ(λ) meta-learning**: First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process). Intelligence growth: `I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗`.
- **Protocol interoperability**: Same structure across all projects (any AI with bash+git).

#### Verification
- Git-based protocol confirmed via README and MEMENTUM.md
- Lambda notation fully specified in MEMENTUM-LAMBDA.md

#### Apply-to-Us
This IS our mementum system. Feed forward patterns into auto-workflow for daemon warm starts. Implement Fibonacci recall: on session start, `git log -n φ^k` for k=2 (4 recent commits) for recent context, deeper for complex topics.

---

## Chapter 2: Own Repos — Context and Memory

### 4. Context Mode — 98% Context Reduction

**Language:** TypeScript
**Repo:** https://github.com/davidwuchn/context-mode

Context window optimization for long-horizon coding agents.

#### Patterns Extracted

- **Think-in-code paradigm**: Instead of dumping 700KB via 47× Read() calls, agent writes a script that computes and returns only the answer. 98% reduction: 315 KB → 5.4 KB.
- **Sandbox tools**: Tool outputs intercepted at boundary. Raw data stored in SQLite, compressed summary returned to LLM context.
- **FTS5 session continuity**: Every edit, git operation, task, error tracked in SQLite with FTS5. On context compaction, retrieves only relevant events via BM25 search — not raw dumps.
- **Output compression**: Agent tool output compressed before context inclusion. Compression ratio tracked per tool.
- **Session continuity**: Tracked via SQLite events. When context compacts, reconstructs relevant state from indexed events.

#### Verification
- Quantitative results: 315 KB → 5.4 KB confirmed
- BM25 + FTS5 implementation confirmed
- Active development

#### Apply-to-Us
Refactor `gptel-auto-workflow-projects.el` analysis passes to accept executable analysis scripts instead of data dumps. Create `workflow--compute` function that accepts elisp analysis scripts, runs them in isolated context, returns only structured results.

---

### 5. GBrain — Self-Wiring Knowledge Graph

**Language:** TypeScript
**Repo:** https://github.com/davidwuchn/gbrain

Zero-LLM-call knowledge graph that auto-wires on page writes.

#### Patterns Extracted

- **Self-wiring graph**: Every page write extracts entity references and creates typed graph edges (attended, works_at, founded, invested_in, married_to) — zero LLM calls. Pure pattern matching.
- **+31.4 P@5 lift**: Graph produces +31.4 percentage points improvement over vector-only RAG.
- **Hybrid search**: P@5 49.1% via reciprocal-rank fusion of vector embeddings + BM25 keyword search. ZeroEntropy embeddings 2.2× faster than OpenAI, wins 11/20 head-to-head queries.
- **Recursive Memory Harness (RMH)**: Hierarchical memory with episodic, semantic, procedural tiers.
- **PageRank scoring**: Graph structure provides implicit importance scoring.

#### Verification
- Quantitative P@5 results confirmed
- Pattern matching approach confirmed
- Active development

#### Apply-to-Us
Implement auto-linking in mementum memory system. Parse `[[wiki/...]]` and `[[people/...]]` style references in memories, create bidirectional links automatically. Consider hybrid search for project history retrieval.

---

## Chapter 3: Own Repos — Agent Architectures

### 6. ECA — Editor Code Assistant

**Language:** Clojure
**Repo:** https://github.com/davidwuchn/eca

"Editor Code Assistant — AI pair programming capabilities agnostic of editor."

#### Patterns Extracted

- **Editor-agnostic protocol**: LSP-inspired communication. Same core works across Emacs, VS Code, Neovim.
- **Multi-model support**: Claude, GPT-4, Gemini, Code Llama — any model via unified interface.
- **Multi-agent / subagent**: Task decomposition into specialized subagents. Orchestration via explicit protocol.
- **Context support**: Project context, session context, task context — layered.
- **MCP resources**: Model Context Protocol for external tool integration.
- **OpenTelemetry**: Distributed tracing for agent operations.
- **EQL-queryable graph**: Datomic-style entity queries over agent state.

#### Verification
- Editor-agnostic protocol confirmed
- Multi-model support confirmed

#### Apply-to-Us
ECA's multi-agent approach directly informs our ECA integration. The LSP-inspired protocol could serve as a model for our internal agent communication. MCP resource support should be leveraged in our tool chain.

---

### 7. Genesis Agent — Self-Verification Engine

**Language:** Bash/TypeScript
**Repo:** https://github.com/davidwuchn/genesis-agent

"Genesis AI agent that writes, verifies, and deploys code autonomously."

#### Patterns Extracted

- **66 deterministic checks**: "The LLM proposes — the machine verifies." AST parsing, exit codes, import resolution, file validation, module signatures.
- **P(success) confidence scoring**: Prior outcomes inform future confidence. `[PLAN]` + `[EXPECT]` with explicit probability estimates.
- **Self-modification loop**: Reads own source code → plans changes → tests in sandbox → verifies output programmatically.
- **Verification gates**: Code not trusted until verification passes. Programmatic assertion over LLM output.
- **Proof-of-work**: Computational work required before certain operations. Prevents abuse.

#### Verification
- 66 deterministic checks confirmed via README
- Self-modification loop confirmed

#### Apply-to-Us
Implement verification functions in Emacs Lisp that check syntax validity, test exit codes, and AST structure BEFORE trusting LLM output. Add P(success) confidence to experiment tracking.

---

### 8. Nucleus — VSM Architecture and Attention Primitives

**Language:** EDN/Emacs Lisp
**Repo:** https://github.com/davidwuchn/nucleus

Viable System Model for AI agent organization with mathematical attention anchors.

#### Patterns Extracted

- **VSM Architecture (S1-S5)**: Viable System Model — Identity (S5), Intelligence (S4), Control (S3), Coordination (S2), Operations (S1). Higher layers change less and matter more.
- **Symbolic Attention Magnets**: Mathematical symbols (φ, fractal, euler, ∃, ∀) with high training weight prime model attention toward formal reasoning. `λ engage(nucleus). [phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA`.
- **Tensor Product Collaboration (⊗)**: `Human ⊗ AI` produces higher quality first attempts than sequential or additive composition.
- **Lambda notation compression**: EDN statecharts and lambda expressions as two notation layers. Prose ↔ formal notation bidirectionally.
- **Mode/Boundary system**: 12 modes (#=code, #=debug, #=review, #=test, #=spec, #=research, etc.) each with defined scope AND explicit "will NOT do" boundaries.
- **Eight Keys as testable predicates**: Each principle (φ, τ, π, μ, ∃, ∀, fractal, e) is a lambda with a test — not just a slogan.
- **Tension pairs**: signal/noise, order/entropy create productive gradients.
- **OODA control loops**: Observe → Orient → Decide → Act as anchoring methodology.
- **Skills structure**: Self-contained skills ≤350 lines, frontmatter metadata.
- **Fibonacci recall depth**: φ^k scaling for memory retrieval based on complexity.
- **Criticality-driven storage**: Only store when effort > 1 attempt AND likely to recur.

#### Verification
- VSM architecture confirmed via README
- Symbolic attention system confirmed
- Mode/boundary system confirmed

#### Apply-to-Us
Add nucleus-style preamble to gptel-system-prompt using mathematical symbols. Use VSM model to organize agent system modules (identity → goals, intelligence → adaptation, control → resource mgmt). Implement mode constraints with explicit "will NOT do" boundaries.

---

## Chapter 4: Own Repos — Tooling and Integration

### 9. gptel (karthink) — Multi-Backend LLM Client

**Package:** elpa/gptel
**Repo:** https://github.com/karthink/gptel

Emacs LLM client with tool-use, MCP integration, and multi-backend support.

#### Patterns Extracted

- **FSM request lifecycle**: INIT → WAIT → TYPE → TOOL → DONE states. Finite state machine for request management.
- **Multi-backend abstraction**: gptel-openai, gptel-ollama, gptel-anthropic, gptel-gemini — each implements `gptel-backend` interface via `cl-defmethod`.
- **Tool-use infrastructure**: `gptel-make-tool` creates tools with name, description, parameters. Tools confirmed before execution.
- **MCP integration**: Uses `mcp.el` for Model Context Protocol. External servers provide tools dynamically.
- **Preset system**: Bundled configurations (temperature, max-tokens, system prompt) per use case.
- **Non-blocking streaming**: Will never block Emacs — async throughout.
- **Temperature nil default**: Backend-specific defaults; backends disagree on scale so gptel defaults to nil.

#### Verification
- FSM confirmed via source code analysis
- Multi-backend confirmed via documentation
- MCP integration confirmed

#### Apply-to-Us
Leverage gptel's existing tool infrastructure. Our agent system should use gptel as the LLM backend rather than building custom HTTP calls. The preset system could inform our experiment configuration management.

---

### 10. gptel-agent (karthink) — Subagent Delegation

**Package:** elpa/gptel-agent
**Repo:** https://github.com/karthink/gptel-agent

Subagent delegation system for gptel.

#### Patterns Extracted

- **Sub-agent delegation via Markdown/YAML frontmatter**: Agent specs as files with YAML frontmatter for name, description, tools, pre-hook.
- **Three agent types**:
  - `executor` — autonomous, full tool access
  - `researcher` — read-only, no mutating tools
  - `introspector` — Emacs introspection, examines buffer state
- **Context isolation**: Sub-agents don't share context with main session. Returns concise reports.
- **Skill directory scanning**: `gptel-agent-skill-dirs` scans `~/.claude/skills/`, `.agents/skills/`, etc. for skill definitions.
- **@mentions for delegation**: Include `@agent-name` in prompt to delegate to named agent.
- **Planning vs Execution presets**: `gptel-plan` (read-only, planning) vs `gptel-agent` (full tools).
- **Parallel delegation**: Multiple agents can work concurrently.

#### Verification
- Package confirmed on MELPA
- YAML frontmatter format confirmed
- Three agent types confirmed

#### Apply-to-Us
Our ECA subagent system could adopt YAML frontmatter for agent specs. The `@mention` delegation pattern is elegant — natural language delegation to named agents. Skill directory scanning could auto-discover our agent configurations.

---

### 11. ai-code-interface.el — Unified Multi-Provider Interface

**Language:** Emacs Lisp
**Repo:** https://github.com/davidwuchn/ai-code-interface.el

"Unified Emacs interface supporting OpenAI Codex, GitHub Copilot CLI, Claude Code, Gemini CLI, Opencode."

#### Patterns Extracted

- **Provider normalization**: Same interface for Codex, Copilot CLI, Claude Code, Gemini CLI, Opencode.
- **Output parsing**: Provider-specific output formats normalized to common structure.
- **Command dispatch**: `ai-code-call` routes to correct provider binary.

#### Verification
- README confirmed
- Five providers documented

#### Apply-to-Us
Provider normalization pattern informs our multi-backend approach. Standardize output parsing across all LLM backends.

---

## Chapter 5: Own Repos — Supporting Systems

### 12. Efrit — Native Elisp Coding Agent

**Language:** Emacs Lisp
**Repo:** https://github.com/davidwuchn/efrit

Native Elisp coding agent with circuit breakers and session buffer UI.

#### Patterns Extracted

- **Pure executor principle**: 35+ tools provided to Claude, Claude makes all decisions, client executes. Zero client-side intelligence.
- **Circuit breaker**: Monitors failure rates per provider, transitions through CLOSED → OPEN → HALF_OPEN states.
- **Checkpoint/restore**: State snapshots before risky operations.
- **Tool receipts**: Every tool execution generates structured metadata for audit trail.
- **Session buffer UI**: Expandable tool calls, TODO tracking, mid-session guidance via `i` key injection.
- **Automatic retry with backoff**: Configurable retry on transient failures.
- **Security controls**: Shell commands have allowed/forbidden pattern matching.

#### Verification
- 35+ tools confirmed
- Circuit breaker implemented

#### Apply-to-Us
Adopt efrit's agent session buffer UI pattern. Implement checkpoint/restore for agent sessions. Use `vc-git` for state snapshots. The pure executor principle — agent decides, elisp executes — is the right model.

---

### 13. Gastown — Multi-Agent Workspace Orchestration

**Language:** Bash
**Repo:** https://github.com/davidwuchn/gastown

Git-worktree persistence for multi-agent coordination.

#### Patterns Extracted

- **Beads ledger**: Work state persisted as immutable git commits with typed metadata (task, status, agent-id). Scales to 20-30 agents.
- **Three-tier watchdog**:
  - **Witness** — session lifecycle management
  - **Deacon** — continuous background patrol
  - **Dogs** — dispatched cleanup/error recovery workers
- **Convoy system**: Work items bundled with autonomous stall detection.
- **Git-worktree isolation**: Per-task worktrees prevent cross-contamination.
- **Escalation routing**: CRITICAL / HIGH / MEDIUM priority routing with hook system.
- **Mailboxes + handoffs**: Agent-to-agent message passing with persistent state.

#### Verification
- Beads ledger confirmed in README
- Scales to 20-30 agents confirmed
- Three-tier watchdog confirmed

#### Apply-to-Us
Implement `gptel-work-bead` creating git commits with structured metadata for tasks. Enable recovery and audit trail. Consider worktree isolation for experiment runs. The three-tier watchdog (Witness/Deacon/Dogs) maps to our daemon architecture.

---

### 14. Psi — Statechart-Driven Agent

**Language:** Clojure
**Repo:** https://github.com/davidwuchn/psi

Statechart-driven agent with EQL-queryable graph.

#### Patterns Extracted

- **Statechart-driven FSM**: All agent states explicit, transitions modelable and composable.
- **EQL-queryable graph**: Datomic-style entity query over agent state.
- **Minimal built-in behavior**: Extensions can completely customize the agent.
- **Everything introspectable**: Full observability of agent internals at all times.
- **Extension protocol**: Third-party can hook into any part of the agent pipeline.

#### Verification
- Statechart architecture confirmed
- EQL query system documented

#### Apply-to-Us
Implement statechart-based workflow in auto-workflow — define explicit states (researching, analyzing, implementing, verifying). Use EQL-style queries over experiment state for introspection.

---

## Chapter 6: External Sources — Orchestration and Context

### 15. ACON — Context Compression via Guideline Optimization

**Source:** arXiv:2510.00615 (Microsoft Research)
**URL:** https://arxiv.org/abs/2510.00615

Context compression that learns from its own failures.

#### Pattern Extracted

- **Compression guideline optimization**: Instead of static compression rules, an LLM analyzes *why* compressed context failed and updates compression guidelines iteratively.
- **Process**: Analyze failures → update guidelines → validate → iterate.
- **Results**: 26-54% memory reduction while preserving >95% accuracy.
- **Key insight**: The compressor learns which parts of tool output are essential vs. noise over multiple sessions.
- **Contrast with static compression**: Static truncation loses important context; adaptive guideline optimization preserves critical information.

#### Verification
- arXiv paper, Microsoft Research
- Quantitative results provided

#### Apply-to-Us
Implement `gptel-tools-compress` that iteratively refines compression guidelines based on task failure analysis. Instead of static truncation, maintain a `compression-guidelines.md` that gets updated after each experiment. This directly builds on our existing `strategy-experiment-velocity-context.el`.

---

### 16. Azure AI Agent Orchestration Patterns

**Source:** Microsoft Azure Architecture Guide
**URL:** https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns

Production-vetted orchestration patterns at five complexity levels.

#### Patterns Extracted

- **5-level complexity spectrum**:

| Level | Pattern | Use When |
|-------|---------|----------|
| 1 | Direct model call | Single-step, prompt engineering suffices |
| 2 | Single agent + tools | Varied queries, dynamic tool use, iteration limits |
| 3 | Sequential | Linear dependencies, progressive refinement |
| 4 | Concurrent (fan-out/fan-in) | Independent perspectives, parallel processing |
| 5 | Hierarchical | Master-slave coordination, complex delegation |

- **Maker-Checker loop**: Two agents in turn-based loop — maker creates, checker validates against explicit acceptance criteria. Max iterations cap prevents infinite loops.
- **Magentic orchestration**: Manager agent builds a "task ledger" (plan with goals/subgoals) dynamically, then delegates to specialized agents. Focuses on *building and documenting* the approach, not just executing.
- **Group chat**: Shared conversation with chat manager routing messages.
- **Handoff**: Explicit transfer of context/state between agents with protocol.

#### Verification
- Official Microsoft documentation
- Well-established production patterns

#### Apply-to-Us
Implement maker-checker loop in `gptel-code-review` mode — one agent writes code, another validates against criteria, iterating until pass or max iterations. Add explicit task ledger buffer for agent planning. Our system currently operates at Level 2-3; fan-out (Level 4) is a future capability.

---

### 17. Multi-Agent Orchestration Framework

**Source:** arXiv:2601.13671v1
**URL:** https://arxiv.org/abs/2601.13671

Formal framework for foundation model orchestration.

#### Patterns Extracted

- **Four-layer orchestration architecture**:
  1. **Planning** — goal decomposition, task scheduling
  2. **Policy** — behavior rules, constraints
  3. **Execution** — tool invocation, state updates
  4. **State** — checkpoint, recovery
- **MCP protocol**: Agent-to-tool communication standard (Model Context Protocol).
- **A2A protocol**: Agent-to-agent peer communication standard (Agent-to-Agent).
- **State + Knowledge separation**: "Separation of operational state from knowledge state preserves modularity."
- **Error classification taxonomy**: Categorize errors by type for targeted recovery.
- **Quality assurance layer**: Validation checkpoints after each orchestration phase.

#### Verification
- arXiv paper
- Multi-agent focus

#### Apply-to-Us
Separate operational state (conversation context) from domain knowledge (project facts) in our agent. Add explicit quality gates between workflow phases. MCP and A2A protocols should inform our internal agent communication design.

---

## Chapter 7: External Sources — Error Recovery and Self-Evolution

### 18. Agent Error Recovery Patterns

**Source:** callsphere.ai + aiagentsblog.com
**URL:** https://aiagentsblog.com/blog/agent-error-recovery-patterns/

Production-vetted patterns for resilient AI agents.

#### Patterns Extracted

- **Circuit breaker with graduated degradation**: CLOSED → DEGRADED → OPEN → HALF_OPEN. DEGRADED allows graceful capability reduction before hard stop. After 3 failures → disable risky tools, add human review flag, switch to conservative mode before hard stop.
- **Per-model circuit breakers**: Isolate failures per provider — one model's cascade doesn't take down all others.
- **Exponential backoff with jitter**: `delay = min(base * 2^attempt + random_jitter, max_delay)`.
- **Fallback chains**: Priority-ordered provider list. Try A → B → C → human review.
- **Error classification**: Retryable (timeout, rate limit) vs. fatal (auth, schema) — different handlers.
- **Five failure categories**: Hard (invalid input), Structural (schema mismatch), Semantic (logic error), Behavioral (policy violation), Resource (quota/timeout).
- **Self-correction loops**: Output validators check results before returning to agent.
- **Graceful degradation**: Capability flags disable risky features progressively.
- **Resilience metrics**: Track MTTR, error rate, fallback rate per backend.

#### Verification
- Multiple independent sources confirm patterns
- Production-vetted

#### Apply-to-Us
Enhance `provider-error-analyzer.el` with graduated DEGRADED state. After 3 failures → disable risky tools, add human review flag. Implement resilience metrics tracking (MTTR, error rate per backend).

---

### 19. Three-Loop Meta-Learning Architecture

**Source:** arXiv:2508.00271 (HyperAgents)
**URL:** https://arxiv.org/abs/2508.00271

Self-evolving agents with explicit metacognition.

#### Pattern Extracted

- **Three-loop architecture**:
  1. **Task execution loop**: ReAct-style (think-act-observe)
  2. **Evaluation loop**: Test-based feedback
  3. **Self-improvement loop**: Metacognitive self-modification
- **Meta tool learning**: Starts minimal, generates help requests on knowledge gaps, routes to tools via dedicated router.
- **Self-reflection + answer verification**: Distill experience into concise texts, dynamically incorporate into future contexts.
- **Experience replay**: Past successful trajectories used to guide future decisions.
- **Results**: Significant improvement in multi-task generalization.

#### Verification
- arXiv paper
- Self-evolution focus

#### Apply-to-Us
Implement three-loop structure in auto-workflow: execution (ReAct) → evaluation (grader) → self-improvement (meta-learner). Add experience replay buffer. This is the conceptual foundation for our `gptel-auto-workflow-evolution.el`.

---

### 20. DSPy Automated Prompt Optimization

**Source:** arXiv:2604.04869 (Stanford)
**URL:** https://arxiv.org/abs/2604.04869

Declarative pipeline compilation and prompt optimization.

#### Pattern Extracted

- **Declarative pipeline compilation**: Define program structure, DSPy compiles to optimized prompts.
- **Results**: 30-45% improvement in factual accuracy, 25% reduction in hallucination rates.
- **Unified architecture**: Symbolic planning + gradient-free optimization + automated module rewriting.
- **APO (Automated Prompt Optimization)**: "Natural language gradient descent" — LLM examines failures, generates critique, edits prompt.
- **OPRO**: LLM as optimizer with meta-prompt showing prior solutions and scores. Maintain table of past strategies with scores, feed to LLM when generating new strategies.
- **Evolutionary prompt search**: EvoPrompt uses genetic algorithms for prompt space exploration.

#### Verification
- arXiv paper with quantitative results
- Stanford research

#### Apply-to-Us
Our auto-workflow already does hypothesis-driven experimentation. Add the "natural language gradient" pattern: after each experiment, have LLM analyze why it failed, generate critique, guide next hypothesis. Maintain OPRO-style strategy table (our `results.tsv` already tracks this).

---

## Chapter 8: External Sources — Memory and Integration

### 21. Memory Taxonomy for Autonomous LLM Agents

**Source:** arXiv:2603.07670v1
**URL:** https://arxiv.org/abs/2603.07670

Comprehensive taxonomy of memory mechanisms for autonomous agents.

#### Pattern Extracted

- **Five mechanism families**:
  1. Context-resident compression
  2. Retrieval-augmented stores
  3. Reflective self-improvement
  4. Hierarchical virtual context
  5. Policy-learned management
- **Write-manage-read loop**: Explicit lifecycle for all memory operations.
- **Cross-task generalization**: Memory architectures that transfer across benchmarks.
- **Modular design space**: encode → store → retrieve → manage.

#### Verification
- arXiv paper
- Comprehensive taxonomy

#### Apply-to-Us
Our mementum integration should adopt the write-manage-read loop explicitly. Add policy-learned management — let the agent learn which memories to store based on retrieval success.

---

### 22. gptel + MCP.el Integration Patterns

**Source:** sukany.cz + blog.kaorubb.org
**URL:** https://sukany.cz/gptel-setup/

Practical gptel setup patterns from real-world usage.

#### Patterns Extracted

- **Multi-backend centralized config**: Model preference list with fallthrough.
- **Dynamic model discovery**: Fetch available models from API at startup.
- **Model name normalization**: Handle dots vs dashes (e.g., `gpt-4o` vs `gpt4o`).
- **gptel-rewrite dispatch mode**: Accept/Reject/Diff/Merge for editing responses.
- **Three-layer tool ecosystem**: llm-tool-collection, ragmacs, gptel-got.
- **curl over url.el**: Corporate proxy compatibility via curl.
- **Copilot auth flow**: Session token caching for persistent auth.
- **gptel-org-branching-context**: Independent questions with shared global context.
- **Topic restriction**: Limit context to specific topics for focused conversations.

#### Verification
- Blog post with setup guide
- Multiple backends tested

#### Apply-to-Us
Leverage existing gptel features: branching context, topic restriction, response editing. Our agent system should use gptel-org-branching-context for parallel research tasks. Dynamic model discovery could inform our backend selection.

---

## Chapter 9: Cross-Cutting Synthesis

### A. Patterns Already Implemented in Our System

From the research, our system already has significant coverage:

| Pattern | Our Implementation |
|---------|-------------------|
| Provider abstraction | gptel multi-backend |
| Circuit breaker | provider-error-analyzer.el |
| Sandbox | gptel-sandbox.el |
| SOP engine | workflow phases in auto-workflow |
| Context compression | strategy-experiment-velocity-context.el |
| Memory system | mementum state.md + memories/knowledge/ |
| Subagent system | ECA with code/plan/executor/reviewer |
| Tool receipts | gptel-tools-programmatic.el |
| Grader-fixer cycle | auto-workflow verification |
| Experiment pipeline | gptel-auto-workflow-*.el |
| VSM architecture | AGENTS.md preamble |
| Fallback chains | provider-error-analyzer.el |
| Self-modification | gptel-auto-workflow-evolution.el |

**Coverage assessment**: Our system has strong coverage of infrastructure patterns (provider abstraction, sandboxing, error handling) and good coverage of workflow patterns (verification, experimentation). Gaps remain in multi-agent orchestration (maker-checker, task ledger) and advanced memory (write-manage-read loop, hybrid search).

---

### B. Patterns NOT Yet Implemented

| Pattern | Source | Priority | Difficulty |
|---------|--------|----------|------------|
| Maker-checker loop | Azure | HIGH | MEDIUM |
| ACON compression guidelines | arXiv:2510.00615 | HIGH | HARD |
| Task ledger | Azure | MEDIUM | MEDIUM |
| Write-manage-read memory loop | arXiv:2603.07670 | MEDIUM | HARD |
| Three-loop meta-learning | arXiv:2508.00271 | HIGH | MEDIUM |
| Hybrid vector + BM25 search | gbrain | MEDIUM | HARD |
| Self-wiring knowledge graph | gbrain | MEDIUM | HARD |
| Graduated circuit breaker (DEGRADED state) | callsphere.ai | MEDIUM | MEDIUM |
| Checkpoint/restore | efrit, zeroclaw | MEDIUM | MEDIUM |
| Think-in-code context reduction | context-mode | HIGH | HARD |
| Symbolic attention magnets | nucleus | LOW | EASY |
| Mode/boundary constraints | nucleus | MEDIUM | EASY |
| OPRO strategy table | arXiv:2604.04869 | MEDIUM | MEDIUM |
| Self-healing vs. retry | callsphere.ai | MEDIUM | MEDIUM |
| MCP.el integration | sukany.cz | MEDIUM | MEDIUM |
| EQL-queryable state | psi | LOW | HARD |
| Per-model circuit breakers | callsphere.ai | MEDIUM | MEDIUM |

---

### C. Pattern Decision Matrix

| Task Type | Best Pattern | Sources | Our Status |
|-----------|-------------|---------|------------|
| Code generation | Maker-checker loop | Azure, genesis-agent | NOT IMPLEMENTED |
| Error recovery | Circuit breaker + self-heal | callsphere.ai, efrit | PARTIAL |
| Context management | ACON + think-in-code | arXiv:2510.00615, context-mode | PARTIAL |
| Memory | Write-manage-read + hybrid search | arXiv:2603.07670, gbrain | PARTIAL |
| Self-evolution | Three-loop + OPRO | arXiv:2508.00271, arXiv:2604.04869 | PARTIAL |
| Multi-agent | Handoff + task ledger | Azure, eca, gastown | PARTIAL |
| Minimal footprint | Nullclaw design | nullclaw | NOT APPLIED |
| Formal reasoning | Symbolic attention magnets | nucleus | NOT APPLIED |
| Provider failover | Per-model circuit breakers | callsphere.ai, zeroclaw | PARTIAL |
| Verification | Genesis-style deterministic checks | genesis-agent | PARTIAL |

---

### D. Architecture Decision Records

**ADR-001: Use gptel as LLM backend**
- Decision: Use gptel for all LLM interactions rather than raw HTTP calls
- Rationale: Handles multi-backend, streaming, MCP integration out of the box
- Status: Implemented

**ADR-002: Multi-backend fallback chain**
- Decision: Implement priority-ordered fallback: OpenAI → Anthropic → Ollama → human review
- Rationale: Zeroclaw's fallback chains proven in production
- Status: Partial — provider-error-analyzer.el has fallback but no explicit chain

**ADR-003: Verify before trust**
- Decision: All LLM output must pass deterministic verification before commit
- Rationale: Genesis-agent's 66-check approach prevents cascading errors
- Status: Partial — verification exists but not enforced for all operations

**ADR-004: Context compression via sandbox**
- Decision: Tool outputs stored in SQLite, compressed summaries in context
- Rationale: Context-mode achieves 98% reduction; essential for long sessions
- Status: Planned — strategy-experiment-velocity-context.el exists but not fully integrated

**ADR-005: Three-loop self-evolution**
- Decision: Execution → Evaluation → Self-improvement as explicit phases
- Rationale: HyperAgents (arXiv:2508.00271) demonstrates significant improvement
- Status: Partial — auto-workflow-evolution.el implements loop but not explicitly three-tier

---

### E. Research Meta-Analysis

**Source effectiveness**:
- Own repos: 0.60 (HIGH) — consistently provide implementable patterns
- External arXiv: 0.30 (MEDIUM) — quantitative results but need adaptation
- External blogs: 0.20 (LOW) — qualitative but hard to verify
- Azure docs: 0.40 (MEDIUM) — production patterns, good for architecture

**Retention rate**: 12% — most patterns either already implemented or not applicable to Emacs Lisp

**Highest-value patterns** (by retention likelihood):
1. Maker-checker loop (Azure) — directly implementable
2. ACON compression guidelines (arXiv) — novel and powerful
3. Three-loop meta-learning (arXiv) — conceptual fit with existing evolution.el
4. Graduated circuit breaker (callsphere.ai) — natural extension of provider-error-analyzer
5. Think-in-code context reduction (context-mode) — high impact, matches existing strategy

**Research quality**: Measured by downstream experiment success rate. Patterns that produce measurable improvement in results.tsv are retained; patterns that fail to improve outcomes are discarded.

---

*Generated by auto-workflow-research-daemon*
*Research turns: 14 | Total findings: 105 | Kept: 13 | Confidence: 0.60*
*Sources: 11 own repos + 5 arXiv papers + 5 external blogs*
