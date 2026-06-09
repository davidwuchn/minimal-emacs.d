<!--
Synthesis verification:
- Confidence: 24%
- Sources: 38 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'research-research-persisted'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize a series of research memories into a comprehensive knowledge page. Let me analyze what I have:

The memories are all from a "persisted-findings" strategy of an auto-workflow research pipeline. They're documenting research digests from external research turns focused on improving an Emacs-based AI agent system (gptel-tools/auto-workflow).

Key recurring patterns across the memories:
1. **Research pipeline patterns**: Researcher daemon failures, local fallback, EMA confidence, beta values, probe/deep-read modes
2. **Source effectiveness**: own repos (high) vs external (medium), kept/not-kept rates
3. **Three priority repos**: nucleus (prompt language), mementum (git memory), gptel (LLM backend)
4. **Key patterns extracted**:
   - gptel FSM pattern (pause/resume multi-stage)
   - mementum 3-tier memory (state/memories/knowledge)
   - nucleus attention magnets, EBNF grammar, prompt debugger, safe-compile
   - DSPy signature/module/optimizer pattern
   - Reflexion verbal self-reflection
   - GEPA reflective prompt evolution
   - Layered error defense (retry+jitter, circuit breaker, fallback)
   - Three-tier watchdog (Witness/Deacon/Dogs)
   - Context-mode sandboxing + FTS5
   - Think-in-Code paradigm
   - MAST failure taxonomy
   - mcp.el hub pattern
   - Stageable pause/resume
   - Durable execution / checkpointing
   - MemGPT two-tier memory
   - A-MEM Zettelkasten
   - Anti-sycophancy system prompts
5. **System context**:
   - auto-workflow module: lisp/modules/gptel-auto-workflow-*.el
   - Tools agent: lisp/modules/gptel-tools-agent-*.el
   - Staging pipeline: staging-scope, staging-config, staging-review, staging-verification, staging-merge
   - Benchmarks: gptel-benchmark-*.el
   - Mementum integration: gptel-auto-workflow-mementum.el
   - FSM utils: gptel-ext-fsm-utils.el
6. **Recurring failure modes**: validation/timeout errors, 0% keep rates on most runs, researcher daemon death, pipeline defects
7. **Key learnings**:
   - Need structured, machine-parseable research outputs
   - Each experiment needs non-none research hash
   - Preserve feedback loop
   - Fail-fast on daemon disappearance
   - Self-evolution observability through TSV metadata

Let me organize this into a comprehensive knowledge page with concrete examples, actionable patterns, and cross-references. I need 50+ lines of actual content.

I'll structure it like:
1. Overview / context
2. The three priority repos (nucleus, mementum, gptel) - core substrate
3. Key research patterns extracted (organized by category)
4. The auto-workflow pipeline architecture
5. Failure modes & mitigations
6. Local fallback protocol
7. Source-effectiveness scoring
8. Cross-references / related topics

Let me write this as a comprehensive knowledge page.