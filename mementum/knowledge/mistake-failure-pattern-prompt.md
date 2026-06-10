<!--
Synthesis verification:
- Confidence: 12%
- Sources: 7 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-prompt', Very short content (28 lines)
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize a series of mistake/failure pattern memories into a comprehensive knowledge page. The memories are all about "failure type: prompt" affecting various gptel-related Emacs Lisp modules. Let me analyze the patterns:

1. **Common target pattern**: All failures target `lisp/modules/gptel-*.el` files - specifically modules in the gptel ecosystem
2. **Failure type**: All are "prompt" failures - meaning issues with the prompts being used
3. **Categories involved**: :programming (keep-rate 3.5%), :agentic (keep-rate 4.3%)
4. **Occurrences**: Range from 3-5 per pattern
5. **Trend data**: Various time ranges showing persistence
6. **Common characteristics**: "Example reasons: none" - which is itself a metadata issue

Key observations:
- All targets are in `lisp/modules/gptel-*.el` 
- Modules affected include: agent-prompt-build, agent-benchmark, benchmark-principles, auto-workflow-strategic, auto-workflow-projects, auto-workflow-ontology-router, auto-workflow-evolution
- This suggests the failure is in shared prompt infrastructure
- "Example reasons: none" indicates the failure detection system isn't capturing root causes
- The dates cluster around 2026-06-07 to 2026-06-08

Let me build a knowledge page with:
- Frontmatter
- Overview section
- Pattern analysis
- Affected modules table
- Root cause hypotheses
- Detection gaps (no example reasons)
- Actionable remediation patterns
- Code examples
- Cross-references

I need to make this 50+ lines minimum with concrete content.