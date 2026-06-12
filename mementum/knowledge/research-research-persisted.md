<!--
Synthesis verification:
- Confidence: 80%
- Sources: 38 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

The user wants me to synthesize the research memories into a knowledge page. Let me look at what's been collected across all the research sessions and create a comprehensive knowledge page with:
1. Frontmatter
2. 50+ lines of content
3. Concrete examples (code, tables, commands)
4. Actionable patterns
5. Cross-references to related topics

Let me distill the recurring themes from all the research memories:

**Key patterns across all research sessions:**

1. **gptel FSM pattern** - STATE/TABLE/HANDLERS/INFO plist, async handlers, process sentinel support. Pause/resume multi-stage requests. INFO is serializable. Targets timeout/validation failures.

2. **mementum three-tier storage** - state.md (working) / memories/ (raw obs ≤200 words) / knowledge/ (synthesized). Seven operations. Human governance layer.

3. **nucleus prompt debugger + EBNF grammar** - Bidirectional prose↔EDN compiler. Attention magnets (φ, ε, τ, π, μ, ∃, ∀). Logprob-based prompt validation. Safe-compile/safe-diagnose for untrusted prompts.

4. **gptel + mcp.el integration** - Org topic-restriction, branching-context, gptel-quick. mcp-hub pattern with declarative server list.

5. **DSPy Signature+Module+Optimizer** - Typed IO signatures, swappable modules (Predict/CoT/ReAct), GEPA/MIPROv2 auto-tune. 0.41→0.63 F1, Shopify 550x cost reduction.

6. **Reflexion** - Verbal self-reflection on failure, stored in episodic memory, 91% pass@1 on HumanEval.

7. **GEPA (Reflective Prompt Evolution)** - Pareto NL reflection beats GRPO with 35× fewer rollouts.

8. **EvolveR** - Offline self-distillation: trajectories→principles→semantic dedup+scoring.

9. **Layered error defense** - Retry+jitter (60-80% thundering-herd cut) → error classification (transient/permanent/content/soft) → circuit breaker (5/60s) → provider fallback.

10. **Durable execution** - Checkpoint-resume; 92% latency reduction.

11. **MAST failure taxonomy** - 40% design / 35% inter-agent / 25% verification.

12. **mcp.el** - Native Emacs MCP client with mcp-hub, mcp-make-text-tool bridge, gptel-mcp.el integration.

13. **Logprob-based prompt validation** - Sample token logprobs before/after preamble injection.

14. **DNS-based memory node discovery** - SRV records for mementum network.

15. **KV cache management** - Snapshot gptel request KV state to disk.

16. **Three-tier watchdog (Gas Town)** - Witness/Deacon/Dogs.

17. **Self-wiring knowledge graph** - Parse [[wiki/...]] references, create typed edges.

18. **Hybrid search (vector + BM25)** - P@5 49.1%, +31.4 lift over vector-only.

19. **DEGRADED state circuit breaker** - 5 failure categories, graduated re-enablement L1/L2/L3.

20. **Self-rewriting meta-prompt loop** - Reflect→Draft→Validate→Persist with quality gate.

21. **Conditional retry with error reinsertion** - Distinguish transient from validation errors.

22. **Context branching** - Org-mode top-level header = global context, sub-headers = isolated conversations.

23. **AI Cliff mitigation** - Multi-model switching mid-session.

24. **Anti-sycophancy directives** - "terse", "challenge assumptions", "avoid flattery".

25. **Think-in-Code paradigm** - LLM writes scripts to process data, not read.

26. **MemGPT two-tier memory** - Context RAM + external disk.

27. **A-MEM Zettelkasten** - 85-93% token reduction.

28. **Sub-agent delegation decision tree** - System-prompt triggers for delegation.

29. **Preview/confirm destructive ops** - Diff before apply.

30. **Tool receipts** - Provider + timestamp + cost metadata for rollback/retry.

31. **MEMENTUM-LAMBDA.md** - Encode protocol itself in nucleus notation.

32. **Context sandboxing** - Routing layer (not LLM layer) achieves 98% reduction.

Now let me structure this into a knowledge page. Given the topic is "research-research-persisted" - this seems to be about the persisted research findings system itself - the patterns discovered, what's been kept vs rejected, and the meta-patterns about how research feeds into the auto-workflow.

Let me write a comprehensive knowledge page that synthesizes all this into actionable patterns.