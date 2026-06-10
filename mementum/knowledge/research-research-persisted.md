<!--
Synthesis verification:
- Confidence: 80%
- Sources: 38 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

The user wants me to synthesize multiple research memory dumps into a single knowledge page about "research-research-persisted". Looking at the memories, I can see they are all research digest outputs from an auto-workflow system, specifically the "persisted-findings" strategy. The key patterns emerging across all these memories are:

1. **Research pipeline architecture** - how the auto-workflow runs research
2. **Source prioritization** - own repos (davidwuchn/*) first, then external
3. **Budget allocation** - token budgets, char limits
4. **Output format** - structured digests with JSON metadata
5. **Failure patterns** - 0% keep rates, local-fallback issues
6. **Local-fallback behavior** - when researcher daemon is missing
7. **Key insights extracted** - FSM patterns, three-tier memory, etc.
8. **Tracking and observability** - findings hashes, research hashes in results.tsv

Let me synthesize this into a comprehensive knowledge page about the persisted-findings research strategy. I need to:
- Include 50+ lines of content
- Concrete examples (code, tables, commands)
- Actionable patterns
- Cross-references

Let me identify the recurring themes:

**Recurring techniques mentioned across memories:**
1. gptel FSM pattern (STATE/TABLE/HANDLERS/INFO)
2. mementum three-tier storage (state.md, memories, knowledge)
3. nucleus prompt debugging
4. Layered error defense (retry+jitter, classify, circuit breaker, fallback)
5. DSPy signature+module pattern
6. Reflexion verbal self-reflection
7. GEPA reflective prompt evolution
8. mcp.el integration
9. gptel-org-branching-context
10. Checkpoint-resume for durability
11. Conditional retry with error reinsertion
12. MemGPT two-tier memory
13. A-MEM Zettelkasten
14. MAST failure taxonomy
15. Logprob-based prompt validation
16. DNS-based memory discovery
17. KV cache management

**Pipeline defects identified:**
- Researcher daemon disappearing (June 3+)
- 0% keep rate consistently
- Validation/timeout errors
- Pipeline hardening needed
- Self-healing patterns
- Watchdog threshold lowering

**Pipeline structure:**
- research-hash: 16-char hex
- targets: list of files
- outcome: kept/total ratio
- strategy: persisted-findings
- local-fallback: when daemon missing
- meta-learning: "Research quality measured by downstream experiment success"

Let me write a comprehensive knowledge page.