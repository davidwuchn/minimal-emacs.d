# Cross-Repo Agent Patterns Distillation

## Research Sources
- ml-intern (davidwuchn/ml-intern): HuggingFace ML engineer agent
- serena (davidwuchn/serena): MCP toolkit with semantic retrieval
- nucleus (local): 8 Keys + VSM + Wu Xing evaluation framework
- gptel-agent (local): Emacs-based LLM agent system

## Core Patterns Discovered

### 1. Nucleus: Mathematical Attention Primers
Symbolic preambles for LLM reasoning, using mathematical notation:
```
[φ fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA
```
- φ (vitality), fractal (clarity), π (synthesis), μ (directness)
- Δ (delta = exact change), λ (lambda = process), Ω (omega = outcome)
- 8 Keys scoring with signal phrases

### 2. Context-Mode: SQLite + FTS5
- 98% context reduction via full-text search
- Semantic chunks + metadata indexing
- Incremental, streaming-aware retrieval

### 3. Efrit: Circuit Breaker Pattern
- Prevents cascade failures in distributed systems
- Half-open → closed → open state transitions
- Safe execution bounds on untrusted code

### 4. Mementum: Git-Based Memory
- Knowledge pages + atomic memories
- Git history for insight persistence
- Human governance over AI-generated content

### 5. Gastown: Git Worktree Coordination
- Parallel worktrees for multi-agent isolation
- Branch naming convention: `optimize/*`
- Worktree-per-task prevents conflicts

### 6. GBrain: Hybrid Search + Knowledge Graph
- BM25 + dense retrieval + reranking
- Typed entity graph (schema.org aligned)
- Memory consolidation from unstructured text

### 7. Genesis-Agent: Verification Gates
- Test-driven development with self-modification
- Emotional state tracking for robustness
- Explicit ASSUMPTION/BEHAVIOR/EDGE CASE comments

### 8. Psi: Statechart-Driven Architecture
- EQL-based introspection for state machine
- Hierarchical states with parallel regions
- Transition guards and actions

### 9. NullClaw/ZeroClaw: Minimal Runtime
- <2ms startup, <700KB footprint
- No external dependencies
- Explicit error propagation

## Cross-Cutting Patterns

| Pattern | Implementation | Source |
|---------|---------------|--------|
| Doom-loop detection | Tool signature tracking (name+args+result) | ml-intern |
| Progressive shortening | Max-char closures with fallback | serena |
| Tool markers (traits) | CanEdit, SymbolicRead, Optional | serena |
| Context×Mode×Project | 3-axis toolset computation | serena |
| Jinja2 prompt templates | Conditional sections based on tools | serena |
| Budget-based approval | Auto-approval up to cost cap | ml-intern |
| Auto-restart on crash | Single retry after LSP restart | serena |
| Event-based init | Lifecycle events vs hooks | local |
| 8 Keys scoring | Signal phrases in commits | nucleus |
| Wu Xing constraints | Anti-pattern thresholds | nucleus |
| LLM degradation detection | Forbidden keywords + expected keywords | local |

## Key Architectural Lessons

1. **Toolset = Context × Mode × Project** (Serena): Three independent axes determine available tools
2. **Symbol-level > File-level** (Serena): LSP-backed symbol operations vs grep
3. **Progressive degradation** (Serena): Truncate → overview → kind counts
4. **Context isolation = subagent** (ml-intern): Each subagent is a fresh session
5. **Memory as first-class tool** (Serena): Memories accessible from agent conversation
6. **Git remembers everything** (Nucleus): Worktree = ephemeral, branch = experiment, main = truth
7. **Test before change** (Genesis): Verification gates before code modification
8. **8 Keys signal phrases** (Nucleus): Explicit markers for automated scoring

## Applicable Improvements for local system

| Gap | Action |
|-----|--------|
| Static prompts | Add Jinja2-style conditional prompts |
| No progressive truncation | Implement max-char closures |
| No tool traits | Add CanEdit/SymbolicRead markers |
| No per-project tool exclusion | Implement project.yml exclusion |
| Grading timeout | Add timer-based fallback |
| No degradation detection | Add forbidden keyword check |
| No auto-restart | Add LSP crash recovery with retry |

## Lambda Summary
```
λ pattern(x). context_mode(x) ⊗ safety(x) ⊗ memory(x) ⊗ isolation(x)
            ⊗ search(x) ⊗ verification(x) ⊗ state(x) ⊗ minimal(x)
```
