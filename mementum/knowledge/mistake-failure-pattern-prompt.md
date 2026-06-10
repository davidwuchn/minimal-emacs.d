<!--
Synthesis verification:
- Confidence: 80%
- Sources: 7 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

The user wants me to synthesize a set of memory entries about a recurring mistake pattern in prompt-related files. Let me analyze the data:

**Pattern observed:** All failures are of type "prompt" affecting files in `lisp/modules/` directory, specifically the `gptel-*` ecosystem. This includes:
- gptel-tools-agent-prompt-build.el (4 occurrences)
- gptel-tools-agent-benchmark.el (5 occurrences, keep-rate 3.5%)
- gptel-benchmark-principles.el (3 occurrences)
- gptel-auto-workflow-strategic.el (3 occurrences, keep-rate 4.3%)
- gptel-auto-workflow-projects.el (3 occurrences, keep-rate 4.3%)
- gptel-auto-workflow-ontology-router.el (3 occurrences)
- gptel-auto-workflow-evolution.el (3 occurrences)

Total: 25 occurrences across 7 files

**Categories affected:** :programming and :agentic (both with very low keep-rates, 3.5% and 4.3%)

**Time range:** 2026-05-30 to 2026-06-08 (about 10 days)

**Key insights:**
1. All targets are in `lisp/modules/` and follow `gptel-*` naming
2. All failures are "prompt" type
3. Two files have tracked keep-rates that are very low (3.5%, 4.3%)
4. No example reasons provided — this is itself a meta-issue
5. The pattern spans the gptel ecosystem: tools/agent, benchmark, auto-workflow

**Synthesis approach:**
- Create a knowledge page documenting the mistake-failure-pattern-prompt
- Provide concrete examples
- Suggest actionable patterns
- Cross-reference related topics

Let me write a comprehensive knowledge page now. I need 50+ lines of content.