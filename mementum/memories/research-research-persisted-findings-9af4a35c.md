# Research: 2026-05-20 23:27

**Strategy:** persisted-findings
**Findings hash:** 9af4a35ccc89d5bf74be4ec3a38352c3888195a3
**Targets:** lisp/modules/gptel-tools-memory.el, lisp/modules/gptel-benchmark-integrate.el, lisp/modules/gptel-ext-core.el, lisp/modules/gptel-tools.el, lisp/modules/gptel-benchmark-memory.el
**Outcome:** 4/24 kept (17%)

**Raw Findings:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-05-20 20:44

Researcher result for task: External research turn 1/4

I'll research these priority repos systematically, starting with own repos as directed. Let me gather findings from multiple sources.Let me read the full content and check a few more critical repos:Now let me synthesize findings from all these priority repos:

## External Sources

### nucleus (davidwuchn/nucleus) — VSM Architecture & Mathematical Attention Anchors
**Pattern**: Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts.
- **Technique**: Use mathematical constants (φ, ψ, Δ, λ) as "attention magnets" to prime LLMs toward formal reasoning patterns
- **How it works**: Tension pairs (signal/noise, order/entropy) create cognitive gradients; control loops (OODA, REPL) anchor execution methodology
- **Application for us**: Implement λ engage(nucleus) preamble for workflow prompts; use formal EDN statecharts for daemon FSM states instead of prose descriptions

### efrit (davidwuchn/efrit) — Native Elisp Coding Agent Architecture  
**Pattern**: Zero client-side intelligence; AI decides, client executes.
- **Technique**: 35+ structured tools with circuit breakers, automatic retry, and security controls
- **How it works**: Session buffer with expandable tool calls, TODO tracking, mid-session guidance (i key injection)
- **Application for us**: Adopt efrit's agent session buffer UI pattern; implement checkpoint/restore for agent sessions

### genesis-agent (davidwuchn/genesis-agent) — Self-Modifying Verification Gates
**Pattern**: Programmatic verification before trust; self-modification loop.
- **Technique**: [PLAN] + [EXPECT] with P(success) confidence scoring based on prior outcomes
- **How it works**: Reads own source code, plans changes, tests in sandbox, verifies output programmatically
- **Application for us**: Implement P(success) confidence tracking in auto-workflow; add verification gates before committing changes

### symphony (davidwuchn/symphony) — Worktree Isolation for Agent Runs
**Pattern**: Isolated workspaces per task, workflow policy in-repo.
- **Technique**: WORKFLOW.md versioned with code, workspace isolation, CI/proof-of-work
- **How it works**: Daemon workflow, per-issue git worktrees, operator oversight at management level not coding level
- **Application for us**: Consider worktree isolation for experiment runs to prevent cross-contamination

### mementum (davidwuchn/mementum) — Git Memory Protocol for Session Continuity
**Pattern**: Feed-forward knowledge via git; three storage types (state/memories/knowledge).
- **Technique**: Human governance (AI proposes, human approves, AI commits); git-native temporal search
- **How it works**: MEMENTUM-LAMBDA.md compressed notation; protocol interoperability across any AI with bash+git
- **Application for us**: This IS our mementum system; feed forward patterns into auto-workflow for daemon warm starts

### gastown (davidwuchn/gastown) — Multi-Agent Workspace Orchestration
**Pattern**: Git-backed hooks for persistent work state; mailboxes and handoffs.
- **Technique**: Polecats (worker agents), Hooks (persistent storage), Beads ledger
- **How it works**: Scales to 20-30 agents with coordination; work state survives restarts
- **Application for us**: Implement persistent work state in hooks for subagent coordination

### gbrain (davidwuchn/gbrain) — Self-Wiring Knowledge Graph
**Pattern**: Zero LLM calls for graph wiring; typed entity edges auto-created on page writes.
- **Technique**: Auto-link extracts [[entity]] refs with typed edges (works_at, founded, attended)
- **How it works**: +31.4 P@5 lift over vector-only RAG; reciprocal rank fusion hybrid search
- **Application for us**: Consider typed-link patterns for knowledge graph integration in mementum

### zeroclaw (davidwuchn/zeroclaw) — Security-First Agent Runtime
**Pattern**: Multi-channel, provider-agnostic with fallback chains; SOP engine.
- **Technique**: Workspace boundaries, command policy, tool receipt
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-9P8t92.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 2/4

Now let me synthesize these findings into actionable insights:

## Research Findings Summary

### External Sources

---

### 1. **Agent Design Pattern Catalogue (arXiv:2405.10467)** — 18 Architectural Patterns
**URL**: https://arxiv.org/abs/2405.10467

**Key Pattern**: Systematic pattern catalogue for foundation model-based agents addressing goal-seeking and plan generation.

- **Technique**: Decision model for selecting appropriate orchestration patterns based on task requirements
- **How it works**: Patterns categorized by context, forces, and trade-offs; supports goal decomposition, tool integration, and accountability
- **Application for us**: Implement pattern decision matrix in auto-workflow controller; map experiment types to optimal agent configurations

---

### 2. **MetaAgent Self-Evolving Paradigm (arXiv:2508.00271)** — Meta Tool Learning
**URL**: https://arxiv.org/abs/2508.00271

**Key Pattern**: Self-improving agent via tool meta-learning without parameter changes.

- **Technique**: Starts minimal, generates help requests on knowledge gaps, routes to tools via dedicated router
- **How it works**: Self-reflection + answer verification → distill experience into concise texts → dynamically incorporate into future contexts
- **Application for us**: Implement P(success) confidence scoring based on outcome history; add "help request" generation when task pattern unrecognized

---

### 3. **Azure AI Agent Orchestration Patterns** — Orchestration Spectrum
**URL**: https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns

**Key Pattern**: 5-level complexity spectrum from direct model call → multiagent orchestration.

| Level | Use When |
|-------|----------|
| Direct model call | Single-step tasks, prompt engineering suffices |
| Single agent + tools | Varied queries, dynamic tool use, iteration limits needed |
| Sequential | Linear dependencies, progressive refinement |
| Concurrent | Independent perspectives, fan-out/fan-in |
| Hierarchical | Master-slave coordination, complex delegation |

- **Application for us**: Our auto-workflow operates at Level 2-3; could implement explicit iteration limits and tool-call budgets

---

### 4. **NVIDIA AI Agent Evaluation Guide** — Trajectory-Aware Metrics
**URL**: https://developer.nvidia.com/blog/mastering-agentic-techniques-ai-agent-evaluation/

**Key Pattern**: Evaluate trajectories, not just final answers.

| Metric | What It Measures |
|--------|------------------|
| **Task Success Rate (TSR)** | Intent resolution within constraints |
| **Tool Call Accuracy** | Precision in function calling, schema compliance |
| **Trajectory Efficiency** | Steps/tokens per success |
| **Reasoning Soundness** | Trace quality, evidence usage |

- **Application for us**: 
  - Log complete trajectories (plans, tool calls, outcomes)
  - Track TSR per experiment type
  - Compute trajectory efficiency as secondary metric
  - Instrument tool usage as first-class signal

---

### 5. **AI Agent Error Recovery Patterns** — 5 Production Patterns
**URL**: https://aiagentsblog.com/blog/agent-error-recovery-patterns/

**Key Patterns**:
1. **Exponential Backoff with Jitter** — Retry delays that increase exponentially with random jitter
2. **Circuit Breakers** — Open circuit after N failures to prevent cascade
3. **Checkpoint-and-Resume** — Save state at each step for partial recovery
4. **Fallback Chains** — Provider A → Provider B → Provider C
5. **Escalation Queues** — Failed tasks moved to human review

**Application for us**:
- Implement checkpoint at each workflow stage (experiment save point)
- Add provider fallback chain (OpenAI → Anthropic → Ollama)
- Circuit breaker after 3 consecutive failures

---

### 6. **Awesome Agents Repository** — Architecture Pattern Taxonomy
**URL**: https://github.com/l-aime/awesome-agents

**Key Architecture Patterns**:

| Category | Patterns |
|----------|----------|
| **Single Agen
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-iTzCe8.txt. Use Read tool if you need more]...

**Digested Insights:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-05-20 20:44

Researcher result for task: External research turn 1/4

I'll research these priority repos systematically, starting with own repos as directed. Let me gather findings from multiple sources.Let me read the full content and check a few more critical repos:Now let me synthesize findings from all these priority repos:

## External Sources

### nucleus (davidwuchn/nucleus) — VSM Architecture & Mathematical Attention Anchors
**Pattern**: Replace verbose prompts with compressed mathematical notation using λ calculus and EDN statecharts.
- **Technique**: Use mathematical constants (φ, ψ, Δ, λ) as "attention magnets" to prime LLMs toward formal reasoning patterns
- **How it works**: Tension pairs (signal/noise, order/entropy) create cognitive gradients; control loops (OODA, REPL) anchor execution methodology
- **Application for us**: Implement λ engage(nucleus) preamble for workflow prompts; use formal EDN statecharts for daemon FSM states instead of prose descriptions

### efrit (davidwuchn/efrit) — Native Elisp Coding Agent Architecture  
**Pattern**: Zero client-side intelligence; AI decides, client executes.
- **Technique**: 35+ structured tools with circuit breakers, automatic retry, and security controls
- **How it works**: Session buffer with expandable tool calls, TODO tracking, mid-session guidance (i key injection)
- **Application for us**: Adopt efrit's agent session buffer UI pattern; implement checkpoint/restore for agent sessions

### genesis-agent (davidwuchn/genesis-agent) — Self-Modifying Verification Gates
**Pattern**: Programmatic verification before trust; self-modification loop.
- **Technique**: [PLAN] + [EXPECT] with P(success) confidence scoring based on prior outcomes
- **How it works**: Reads own source code, plans changes, tests in sandbox, verifies output programmatically
- **Application for us**: Implement P(success) confidence tracking in auto-workflow; add verification gates before committing changes

### symphony (davidwuchn/symphony) — Worktree Isolation for Agent Runs
**Pattern**: Isolated workspaces per task, workflow policy in-repo.
- **Technique**: WORKFLOW.md versioned with code, workspace isolation, CI/proof-of-work
- **How it works**: Daemon workflow, per-issue git worktrees, operator oversight at management level not coding level
- **Application for us**: Consider worktree isolation for experiment runs to prevent cross-contamination

### mementum (davidwuchn/mementum) — Git Memory Protocol for Session Continuity
**Pattern**: Feed-forward knowledge via git; three storage types (state/memories/knowledge).
- **Technique**: Human governance (AI proposes, human approves, AI commits); git-native temporal search
- **How it works**: MEMENTUM-LAMBDA.md compressed notation; protocol interoperability across any AI with bash+git
- **Application for us**: This IS our mementum system; feed forward patterns into auto-workflow for daemon warm starts

### gastown (davidwuchn/gastown) — Multi-Agent Workspace Orchestration
**Pattern**: Git-backed hooks for persistent work state; mailboxes and handoffs.
- **Technique**: Polecats (worker agents), Hooks (persistent storage), Beads ledger
- **How it works**: Scales to 20-30 agents with coordination; work state survives restarts
- **Application for us**: Implement persistent work state in hooks for subagent coordination

### gbrain (davidwuchn/gbrain) — Self-Wiring Knowledge Graph
**Pattern**: Zero LLM calls for graph wiring; typed entity edges auto-created on page writes.
- **Technique**: Auto-link extracts [[entity]] refs with typed edges (works_at, founded, attended)
- **How it works**: +31.4 P@5 lift over vector-only RAG; reciprocal rank fusion hybrid search
- **Application for us**: Consider typed-link patterns for knowledge graph integration in mementum

### zeroclaw (davidwuchn/zeroclaw) — Security-First Agent Runtime
**Pattern**: Multi-channel, provider-agnostic with fallback chains; SOP engine.
- **Technique**: Workspace boundaries, command policy, tool receipt
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-9P8t92.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 2/4

Now let me synthesize these findings into actionable insights:

## Research Findings Summary

### External Sources

---

### 1. **Agent Design Pattern Catalogue (arXiv:2405.10467)** — 18 Architectural Patterns
**URL**: https://arxiv.org/abs/2405.10467

**Key Pattern**: Systematic pattern catalogue for foundation model-based agents addressing goal-seeking and plan generation.

- **Technique**: Decision model for selecting appropriate orchestration patterns based on task requirements
- **How it works**: Patterns categorized by context, forces, and trade-offs; supports goal decomposition, tool integration, and accountability
- **Application for us**: Implement pattern decision matrix in auto-workflow controller; map experiment types to optimal agent configurations

---

### 2. **MetaAgent Self-Evolving Paradigm (arXiv:2508.00271)** — Meta Tool Learning
**URL**: https://arxiv.org/abs/2508.00271

**Key Pattern**: Self-improving agent via tool meta-learning without parameter changes.

- **Technique**: Starts minimal, generates help requests on knowledge gaps, routes to tools via dedicated router
- **How it works**: Self-reflection + answer verification → distill experience into concise texts → dynamically incorporate into future contexts
- **Application for us**: Implement P(success) confidence scoring based on outcome history; add "help request" generation when task pattern unrecognized

---

### 3. **Azure AI Agent Orchestration Patterns** — Orchestration Spectrum
**URL**: https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns

**Key Pattern**: 5-level complexity spectrum from direct model call → multiagent orchestration.

| Level | Use When |
|-------|----------|
| Direct model call | Single-step tasks, prompt engineering suffices |
| Single agent + tools | Varied queries, dynamic tool use, iteration limits needed |
| Sequential | Linear dependencies, progressive refinement |
| Concurrent | Independent perspectives, fan-out/fan-in |
| Hierarchical | Master-slave coordination, complex delegation |

- **Application for us**: Our auto-workflow operates at Level 2-3; could implement explicit iteration limits and tool-call budgets

---

### 4. **NVIDIA AI Agent Evaluation Guide** — Trajectory-Aware Metrics
**URL**: https://developer.nvidia.com/blog/mastering-agentic-techniques-ai-agent-evaluation/

**Key Pattern**: Evaluate trajectories, not just final answers.

| Metric | What It Measures |
|--------|------------------|
| **Task Success Rate (TSR)** | Intent resolution within constraints |
| **Tool Call Accuracy** | Precision in function calling, schema compliance |
| **Trajectory Efficiency** | Steps/tokens per success |
| **Reasoning Soundness** | Trace quality, evidence usage |

- **Application for us**: 
  - Log complete trajectories (plans, tool calls, outcomes)
  - Track TSR per experiment type
  - Compute trajectory efficiency as secondary metric
  - Instrument tool usage as first-class signal

---

### 5. **AI Agent Error Recovery Patterns** — 5 Production Patterns
**URL**: https://aiagentsblog.com/blog/agent-error-recovery-patterns/

**Key Patterns**:
1. **Exponential Backoff with Jitter** — Retry delays that increase exponentially with random jitter
2. **Circuit Breakers** — Open circuit after N failures to prevent cascade
3. **Checkpoint-and-Resume** — Save state at each step for partial recovery
4. **Fallback Chains** — Provider A → Provider B → Provider C
5. **Escalation Queues** — Failed tasks moved to human review

**Application for us**:
- Implement checkpoint at each workflow stage (experiment save point)
- Add provider fallback chain (OpenAI → Anthropic → Ollama)
- Circuit breaker after 3 consecutive failures

---

### 6. **Awesome Agents Repository** — Architecture Pattern Taxonomy
**URL**: https://github.com/l-aime/awesome-agents

**Key Architecture Patterns**:

| Category | Patterns |
|----------|----------|
| **Single Agen
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-iTzCe8.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
