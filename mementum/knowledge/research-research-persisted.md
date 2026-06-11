<!--
Synthesis verification:
- Confidence: 80%
- Sources: 38 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

The user wants me to synthesize multiple research memories into a comprehensive knowledge page about "research-research-persisted". Let me analyze the patterns across all these research digests.

Looking at the memories, I see several distinct categories of findings:

1. **Research Daemon Failure Patterns (Local Fallback)**
   - Researcher daemon has been dying repeatedly
   - Pipeline defect: missing research files after wait
   - Feedback loop preservation: research hash must be non-none
   - Structured research outputs preferred
   - Daemon orchestration boundaries need fail-fast + fallback

2. **gptel FSM / Pause-Resume Pattern**
   - STATE/TABLE/HANDLERS/INFO plist architecture
   - Async handlers via process sentinel
   - Serializable INFO for checkpoint/resume
   - Multi-stage request orchestration

3. **Mementum Three-Tier Memory**
   - state.md (working, <200 words)
   - memories/ (raw observations, <200 words)
   - knowledge/ (synthesized pages)
   - Seven operations: create, create-knowledge, update, delete, search, read, synthesize
   - Human governance: AI proposes → human approves → AI commits
   - DNS-based discovery for protocol interoperability

4. **Nucleus Patterns**
   - Attention magnets (mathematical symbols prime transformer attention)
   - Lambda notation for prompt compression
   - EBNF formal grammar
   - safe-compile/safe-diagnose for untrusted prompts
   - Logprob-based prompt validation

5. **Error Recovery / Circuit Breaker Patterns**
   - DEGRADED state between CLOSED/OPEN
   - Graduated re-enablement (L1 5%, L2 20%, L3 50%)
   - 4-layer defense: retry+jitter → classify → circuit-breaker → fallback
   - 5 failure categories: Hard, Structural, Semantic, Behavioral, Resource
   - Conditional retry with error reinsertion
   - 5-tier graceful degradation: full → reduced → cached → rule-based → graceful failure

6. **DSPy / Self-Evolution Patterns**
   - Signatures as typed IO contracts
   - Modules (Predict, ChainOfThought, ReAct) as swappable strategies
   - Optimizers: GEPA, MIPROv2, BootstrapFewShot
   - Compilation model: save compiled JSON as artifact

7. **Reflexion Pattern**
   - Verbal self-reflection in episodic memory
   - 91% pass@1 on HumanEval
   - Failure → reflection → memory → next attempt context

8. **Context Engineering**
   - AI Cliff: context fixation
   - Context branching via org-mode headers
   - Multi-model switching mid-session
   - Topic restriction via org properties

9. **gptel-agent Patterns**
   - Sub-agent delegation via system prompt decision tree
   - Anti-sycophancy directives
   - Preview/confirm destructive ops
   - Tool hierarchy enforcement (Emacs-native over shell)

10. **Three-Tier Watchdog (gastown)**
    - Witness (session lifecycle)
    - Deacon (continuous background patrol)
    - Dogs (dispatched workers)
    - Convoy system for work bundling

11. **Think-in-Code (context-mode)**
    - 98% context reduction via script execution
    - SQLite FTS5 for session continuity
    - Raw tool output never enters context

12. **Self-Wiring Knowledge Graph (gbrain)**
    - Entity references auto-extracted from markdown
    - Typed graph edges
    - +31.4 P@5 lift over vector-only RAG

13. **Tool Receipts + Workspace Boundaries (zeroclaw)**
    - Provider + timestamp + cost metadata
    - Defense in depth: receipts + boundaries + OS sandboxing

14. **Durable Execution / Checkpointing**
    - Resume from last step on failure
    - 92% latency reduction
    - Event-history replay

15. **MAST Failure Taxonomy**
    - 40% system design / 35% inter-agent / 25% verification
    - 14 failure modes
    - Budget 15-20% for failure handling

16. **Magent (jamie-cui)**
    - Durable child-agent job lifecycle
    - M-x doctor for self-diagnostics
    - Multi-agent Emacs pattern

17. **Hybrid Search (vector + BM25)**
    - P@5 49.1% via hybrid retrieval
    - Reciprocal-rank fusion
    - ZeroEntropy embeddings 2.2x faster

18. **Kernel-level Experimental Outcomes**
    - Most experiments had 0% keep rate
    - 2/56 = 4% (one outlier)
    - 3/9 = 33% (best one)
    - Research quality measured by downstream experiment success
    - Persistent findings needed for auto-workflow

Now I need to organize all this into a comprehensive knowledge page. The topic is "research-research-persisted" — the meta-pattern of persisted research findings for the auto-workflow.

Let me structure this as:

1. **Overview** - What is the persisted research pattern
2. **Pipeline Architecture** - How research flows
3. **Core Patterns** - The key technical patterns discovered
4. **Failure Modes** - The "researcher daemon dead" problem
5. **Storage Hierarchy** - The three-tier memory model
6. **Self-Evolution Loop** - GEPA, Reflexion, DSPy
7. **Error Recovery** - Circuit breaker, durable execution
8. **Context Engineering** - gptel-org-branching-context, topic restriction
9. **Actionable Patterns** - Code-level patterns
10. **Cross-References**

Let me build a detailed page with 50+ lines, code examples, tables, and cross-references.