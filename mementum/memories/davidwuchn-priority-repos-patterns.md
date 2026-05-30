# davidwuchn Priority Repos - Key Patterns

## nucleus (nucleus-mcp, nucleus-agent)
- **Attention Magnets**: φ/∞/Δ/∑/∃/∀/√/π symbols prime LLM attention (low-cost, high-leverage)
- **Lambda Compiler**: prose ↔ lambda for cognitive navigation (translate intent to formal structure)
- **VSM (Value Stream Mapping)**: Distill/Drift cycle - verify system behavior against source code
- **Tension Pairs**: signal/noise, order/entropy as productive gradients (not problems to solve)
- **Self-referential prompts**: λ self_world patterns - agent reflects on its own reasoning process

## gptel (gptel, gptel-mcp)
- **Tool-use agentic mode**: gptel-use-tools t enables agentic tool execution
- **MCP integration**: Model Context Protocol for external tool discovery/execution
- **Context branching**: gptel-org-branching-context for parallel exploration
- **Topic restriction**: gptel-org-set-topic for context window management
- **Multi-backend fallback**: retry chains with automatic backend reordering
- **In-place editing**: pause/resume multi-stage LLM requests
- **LLM introspection**: see exactly what's sent to model before execution

## mementum (mementum, gptel-mementum)
- **Git-based memory**: memories.md, knowledge.md, state.md for cross-session continuity
- **Feed-forward protocol**: encode understanding into git for session compounding
- **Three storage tiers**: working memory / memories (<200 words) / knowledge (synthesized)
- **Seven operations**: create, create-knowledge, update, delete, search, read, synthesize
- **Human governance**: AI proposes, human approves, AI commits (human-in-loop)

## External Novel Patterns (validated)
- **Circuit Breaker** (Martin Fowler): 3-state (Closed→Open→Half-Open) for fault tolerance in LLM calls
- **Self-Evolving Agents** (arXiv 2504.x): 4-component framework (System Inputs→Agent→Environment→Optimizers)
- **Evolution mechanisms**: experience replay, meta-learning, self-supervised correction, skill-augmented evolution
- **Context Engineering**: structured context management to avoid "AI Cliff" (context length limits)
- **Graceful Degradation Ladder**: full-model → fast-model → cache → graceful-failure
- **Elisp Dev MCP Server**: exposes Emacs introspection to AI agents via LSP-equivalent protocol
